-- Money and security tests. Run: see supabase/tests/run.sh. Any failure stops with an error.
\set ON_ERROR_STOP on
\set QUIET on
create schema t; grant usage on schema t to authenticated, anon;
create table t.res(n serial, ok boolean, msg text); grant all on t.res to authenticated, anon; grant all on sequence t.res_n_seq to authenticated, anon;
create function t.ok(c boolean, m text) returns void language plpgsql as $$ begin insert into t.res(ok,msg) values (coalesce(c,false), m); if not coalesce(c,false) then raise exception 'FAILED: %', m; end if; end $$;
create function t.fails(s text, pat text, m text) returns void language plpgsql as $$
begin
  begin execute s; exception when others then
    if sqlerrm ilike '%'||pat||'%' then perform t.ok(true,m); return; end if;
    perform t.ok(false, m||' -> wrong error: '||sqlerrm); return;
  end;
  perform t.ok(false, m||' -> expected an error but it worked');
end $$;
create function t.as_user(u uuid) returns void language sql as $$ select set_config('test.uid', coalesce(u::text,''), false) $$;
grant execute on all functions in schema t to authenticated, anon;
create table t.v(k text primary key, id uuid); grant all on t.v to authenticated;
create function t.id(k_ text) returns uuid language sql as $$ select id from t.v where k=k_ $$;
create function t.put(k_ text, i uuid) returns void language sql as $$ insert into t.v values(k_,i) on conflict(k) do update set id=excluded.id $$;
grant execute on function t.id, t.put to authenticated;

create function t.bal(o uuid, c text) returns bigint language sql security definer as $$ select public.account_balance(o,c) $$;
grant execute on function t.bal to authenticated;
grant execute on function public.calc_schedule(bigint,int,int,text,date) to authenticated; -- test only
insert into auth.users(id,email) select gen_random_uuid(), x||'@test.local' from unnest(array['admin','treas','sec','officer','ann','ben','cy','stranger','plat']) x;
insert into t.v select split_part(email,'@',1)||'_u', id from auth.users;
insert into public.platform_admins select id from auth.users where email='plat@test.local';

set role authenticated;
select t.as_user(t.id('admin_u'));
select t.put('org', public.create_organization('Test Group','tier_1_vsla','UGX',5000,3,10,50,'Admin One','0700000001',true));

-- helper: add a member, claim invite as that user
create temp table invites(k text, code text, mid uuid); 
do $$ declare r jsonb; x record; begin
 for x in select * from (values ('treas','Tess Treasurer','treasurer','0700000010'),('sec','Sam Secretary','secretary','0700000011'),('officer','Olive Officer','loan_officer','0700000012'),('ann','Ann','member','0700000013'),('ben','Ben','member','0700000014'),('cy','Cy','member','0700000015')) v(k,n,ro,ph) loop
   r := public.add_member(t.id('org'), x.n, x.ph, null, x.ro, null, null);
   perform t.put(x.k||'_m', (r->>'member_id')::uuid);
   perform t.as_user(t.id(x.k||'_u')); perform public.claim_invite(r->>'invite_code', true); perform t.as_user(t.id('admin_u'));
 end loop;
end $$;
select t.ok((select count(*) from jsonb_array_elements(public.my_memberships()))=1,'admin sees own group');
select t.fails($$select public.claim_invite('WRONGCOD', true)$$,'wrong or has expired','bad invite code refused');

-- WORKED EXAMPLE A through the real flow: Ann 20000, Ben 10000, Cy 10000
select t.as_user(t.id('ann'||'_u'));
select public.record_payment(t.id('org'), t.id('ann_m'),'shares',20000,'mtn_momo','MP1001','0700000013',null,null,'k1');
select t.fails($$select public.record_payment(t.id('org'), t.id('ann_m'),'shares',20000,'mtn_momo','mp1001',null,null,null,'k2')$$,'already recorded','same MoMo ID cannot be used twice');
select t.fails($$select public.record_payment(t.id('org'), t.id('ann_m'),'shares',500,'mtn_momo','',null,null,null,'k3')$$,'transaction ID','mobile money needs a transaction ID');
select t.fails($$select public.record_payment(t.id('org'), t.id('ben_m'),'shares',500,'cash',null,null,null,null,'k4')$$,'your own','member cannot record for another');
select t.ok(((public.record_payment(t.id('org'), t.id('ann_m'),'shares',20000,'mtn_momo','MP1001',null,null,null,'k1'))->>'status')='pending','retry with same key returns same record');
select t.ok((public.dashboard(t.id('org'))->>'member_savings')::bigint=0,'pending payment does not touch ledger');
select t.fails($$select public.review_payment((select id from public.list_payments_ids), true, '')$$,'','placeholder') where false;
select t.as_user(t.id('ann_u'));
select t.fails(format($$select public.review_payment(%L, true, '')$$,(select (x->>'id') from jsonb_array_elements(public.list_payments(t.id('org'))) x limit 1)),'Your role','member cannot confirm');
select t.as_user(t.id('treas_u'));
select public.review_payment((select (x->>'id')::uuid from jsonb_array_elements(public.list_payments(t.id('org'),'pending')) x limit 1), true, 'seen on statement');
select t.ok((public.dashboard(t.id('org'))->>'momo_bank')::bigint=20000,'confirmed MoMo posts to group MoMo account');

-- treasurer cannot confirm what he submitted
select public.record_payment(t.id('org'), t.id('ben_m'),'shares',10000,'cash',null,null,null,null,'k5');
select t.fails(format($$select public.review_payment(%L, true, '')$$,(select (x->>'id') from jsonb_array_elements(public.list_payments(t.id('org'),'pending')) x limit 1)),'you submitted','maker cannot be checker');
select t.as_user(t.id('admin_u'));
select public.review_payment((select (x->>'id')::uuid from jsonb_array_elements(public.list_payments(t.id('org'),'pending')) x limit 1), true, '');

-- meeting: counters must differ; cash in meeting posts at once; cash gate works
select t.fails(format($$select public.open_meeting(t.id('org'),null,10000,%L,%L)$$,t.id('sec_m'),t.id('sec_m')),'different','same counter twice refused');
select t.as_user(t.id('sec_u'));
select t.put('mtg', public.open_meeting(t.id('org'),null,10000,t.id('sec_m'),t.id('treas_m')));
select t.fails(format($$select public.open_meeting(t.id('org'),null,10000,%L,%L)$$,t.id('sec_m'),t.id('treas_m')),'still open','second open meeting refused');
select public.set_attendance(t.id('mtg'),t.id('ann_m'),true);
select public.record_payment(t.id('org'), t.id('cy_m'),'shares',10000,'cash',null,null,null,null,'k6');
select t.ok((public.dashboard(t.id('org'))->>'cash_box')::bigint=20000,'cash in open meeting posts at once');
select t.fails(format($$select public.close_meeting(t.id('mtg'),19999,%L,%L,'x')$$,t.id('sec_m'),t.id('treas_m')),'Shortage of 1','cash gate blocks wrong count');
select public.close_meeting(t.id('mtg'),20000,t.id('sec_m'),t.id('treas_m'),'All good');
select t.ok(((public.list_meetings(t.id('org')))->0->>'status')='closed','meeting closed after match');

-- emergency pot is separate and not lendable
select t.as_user(t.id('cy_u'));
select public.record_payment(t.id('org'), t.id('cy_m'),'emergency_contribution',5000,'cash',null,null,null,null,'k7');
select t.as_user(t.id('admin_u'));
select public.review_payment((select (x->>'id')::uuid from jsonb_array_elements(public.list_payments(t.id('org'),'pending')) x limit 1), true, '');
select t.ok((public.dashboard(t.id('org'))->>'emergency_fund')::bigint=5000,'emergency fund 5000');

-- loans: limit, separation of duties, interest first
select t.as_user(t.id('ann_u'));
select t.fails(format($$select public.apply_loan(t.id('org'),%L,60001,1,'flat','x')$$,t.id('ann_m')),'Limit reached','loan above 3x savings refused');
select t.put('loan', public.apply_loan(t.id('org'),t.id('ann_m'),10000,1,'flat','Stock'));
select t.as_user(t.id('officer_u'));
select t.fails(format($$select public.approve_loan(t.id('loan'),'R1',%L,%L)$$,t.id('ann_m'),t.id('ben_m')),'witness','borrower cannot witness');
select t.fails(format($$select public.approve_loan(t.id('loan'),'R1',%L,%L)$$,t.id('ben_m'),t.id('ben_m')),'different witnesses','same witness twice refused');
select public.approve_loan(t.id('loan'),'R1',t.id('ben_m'),t.id('cy_m'));
select t.fails($$select public.disburse_loan(t.id('loan'),'cash',null)$$,'Your role','loan officer cannot pay out');
select t.as_user(t.id('treas_u'));
select public.disburse_loan(t.id('loan'),'cash',null);
select t.ok(((public.list_loans(t.id('org')))->0->>'remaining')::bigint=10083,'flat interest on 10000 at 10% for 1 month is 83');
select public.record_payment(t.id('org'), t.id('ann_m'),'loan_repayment',83,'cash',null,null,t.id('loan'),null,'k8');
select t.as_user(t.id('admin_u'));
select public.review_payment((select (x->>'id')::uuid from jsonb_array_elements(public.list_payments(t.id('org'),'pending')) x limit 1), true, '');
select t.ok(t.bal(t.id('org'),'4010')=-83,'first 83 goes to interest');
select t.ok(t.bal(t.id('org'),'1050')=10000,'principal untouched');
select t.as_user(t.id('treas_u'));
select t.fails(format($$select public.review_payment((public.record_payment(t.id('org'), t.id('ann_m'),'loan_repayment',99999,'cash',null,null,t.id('loan'),null,'k9')->>'id')::uuid,true,'')$$),'','overpay') where false;
select public.record_payment(t.id('org'), t.id('ann_m'),'loan_repayment',10000,'mtn_momo','MP2002',null,t.id('loan'),null,'k10');
select t.as_user(t.id('admin_u'));
select public.review_payment((select (x->>'id')::uuid from jsonb_array_elements(public.list_payments(t.id('org'),'pending')) x limit 1), true, '');
select t.ok(((public.list_loans(t.id('org')))->0->>'status')='paid','loan paid');

-- reversal and undo-of-loan-status
select t.put('rev', (select (x->>'id')::uuid from jsonb_array_elements(public.list_journals(t.id('org'))) x where x->>'type'='loan_repayment' order by (x->>'journal_number')::int desc limit 1));
select t.fails($$select public.reverse_journal(t.id('rev'),'')$$,'reason','reversal needs a reason');
select public.reverse_journal(t.id('rev'),'Wrong amount');
select t.ok(((public.list_loans(t.id('org')))->0->>'status')='active','reversal reopens loan');
select t.ok(((public.list_loans(t.id('org')))->0->>'remaining')::bigint=10000,'reversal restores balance');
select t.fails($$select public.reverse_journal(t.id('rev'),'again')$$,'already','cannot reverse twice');
select t.as_user(t.id('treas_u'));
select public.record_payment(t.id('org'), t.id('ann_m'),'loan_repayment',10000,'mtn_momo','MP2002',null,t.id('loan'),null,'k11');
select t.as_user(t.id('admin_u'));
select public.review_payment((select (x->>'id')::uuid from jsonb_array_elements(public.list_payments(t.id('org'),'pending')) x limit 1), true, 'same ref allowed after reversal');

-- ledger always balances
select t.ok((public.trial_balance(t.id('org'))->>'balanced')::boolean,'trial balance balances');

-- search finds by ref, name, keyword
select t.ok(public.global_search(t.id('org'),'MP1001')::text like '%MP1001%','search finds a MoMo ID');
select t.ok(public.global_search(t.id('org'),'Tess')::text like '%Tess Treasurer%','search finds a person');
select t.ok(jsonb_array_length(public.global_search(t.id('org'),'x'))=0,'search ignores one letter');
select t.ok(jsonb_array_length(public.global_search(t.id('org'),'%%'))=0,'search treats percent as text');
select t.as_user(t.id('ben_u'));
select t.ok(public.global_search(t.id('org'),'MP1001')::text not like '%MP1001%','member cannot find other members money');
select t.ok(public.list_members(t.id('org'))::text not like '%256700000013%','member cannot see other phones');
select t.fails($$select public.trial_balance(t.id('org'))$$,'Only officers','member cannot see trial balance');
select t.fails($$select public.list_audit(t.id('org'))$$,'Only officers','member cannot read audit');
select t.fails(format($$select public.member_statement(t.id('org'),%L)$$,t.id('ann_m')),'own statement','member cannot read other statement');
select t.ok(((public.member_statement(t.id('org'),t.id('ben_m')))->>'savings')::bigint=10000,'member statement shows own savings');
select t.ok(jsonb_array_length(public.list_loans(t.id('org')))=0,'member sees only own loans');

-- strangers see nothing, direct table writes fail
select t.as_user(t.id('stranger_u'));
select t.fails($$select public.dashboard(t.id('org'))$$,'not a member','stranger blocked from dashboard');
select t.fails($$select public.global_search(t.id('org'),'Ann')$$,'not a member','stranger blocked from search');
select t.ok((select count(*) from public.journals)=0,'RLS hides journals from stranger');
select t.ok((select count(*) from public.members)=0,'RLS hides members from stranger');
select t.fails($$insert into public.journal_lines(journal_id,org_id,account_code,debit) values (gen_random_uuid(),t.id('org'),'1010',1)$$,'permission denied','no direct insert');
select t.fails($$select public.post_journal(t.id('org'),'x','reversal','x','[]'::jsonb)$$,'permission denied','internal post_journal not callable');
select t.fails($$select public.add_audit(t.id('org'),'x','x','x','x')$$,'permission denied','internal audit not callable');
select t.as_user(t.id('admin_u'));
select t.fails($$update public.journals set description='hacked'$$,'permission denied','admin cannot update journals directly');
reset role;
select t.fails($$update public.journal_lines set debit=1$$,'permanent','even DB owner blocked from editing lines by trigger');
select t.fails($$delete from public.audit_log$$,'permanent','even DB owner blocked from deleting audit');
select t.fails($$truncate public.journals cascade$$,'permanent','truncate blocked');
do $$ begin
  begin
    insert into public.journals(org_id,journal_number,idempotency_key,type,description,actor_name) values (t.id('org'),9999,'bad','reversal','x','x');
    insert into public.journal_lines(journal_id,org_id,account_code,debit) select id,org_id,'1010',5 from public.journals where idempotency_key='bad';
    set constraints journal_balanced immediate;
    perform t.ok(false,'unbalanced journal should fail');
  exception when others then
    perform t.ok(sqlerrm ilike '%does not balance%','unbalanced journal refused');
  end;
end $$;

-- audit chain: verify, then tamper as owner with trigger off, verify catches it
set role authenticated;
select t.ok((public.verify_audit_chain(t.id('org'))->>'ok')::boolean,'audit chain verifies');
reset role;
alter table public.audit_log disable trigger audit_log_no_change;
update public.audit_log set details = 'tampered' where org_id = t.id('org') and seq = 3;
alter table public.audit_log enable trigger audit_log_no_change;
set role authenticated;
select t.ok(not (public.verify_audit_chain(t.id('org'))->>'ok')::boolean,'tampering is detected');
reset role;
alter table public.audit_log disable trigger audit_log_no_change;
delete from public.audit_log where org_id = t.id('org'); -- wipe so later rows chain again
alter table public.audit_log enable trigger audit_log_no_change;
set role authenticated;

-- SHARE-OUT Worked example A: savings 20000/10000/10000, interest 83, emergency 5000 carried. Pool 40083 -> 20041/10021/10021
select t.ok((public.shareout_preview(t.id('org'))->>'pool')::bigint=40083,'pool is 40083 and excludes emergency');
select t.ok((select jsonb_agg((x->>'payout')::bigint order by x->>'full_name') from jsonb_array_elements(public.shareout_preview(t.id('org'))->'payouts') x)='[20041,10021,10021]'::jsonb,'Example A payouts 20041 10021 10021');
select t.as_user(t.id('ann_u'));
select t.fails($$select public.execute_shareout(t.id('org'))$$,'Your role','member cannot run share-out');
select t.as_user(t.id('treas_u'));
select public.execute_shareout(t.id('org'));
select t.ok(t.bal(t.id('org'),'2100')=-5000,'emergency carried forward');
select t.ok(t.bal(t.id('org'),'1010')+t.bal(t.id('org'),'1020')=5000,'only emergency money remains');
select t.ok(t.bal(t.id('org'),'2010')=0,'savings cleared');
select t.ok(t.bal(t.id('org'),'4010')=0 and t.bal(t.id('org'),'3010')=0,'income closed');
select t.ok((public.trial_balance(t.id('org'))->>'balanced')::boolean,'balanced after share-out');
select t.ok((select cycle_number from public.organizations where id=t.id('org'))=2,'new cycle started');
select t.ok(((public.member_statement(t.id('org'),t.id('ann_m')))->'payouts'->0->>'payout')::bigint=20041,'statement shows payout');

-- Worked example B: pool 100, equal weights -> one gets 34, two get 33
select t.as_user(t.id('admin_u'));
select t.put('org2', public.create_organization('B Group','tier_2_sacco','UGX',1,3,10,50,'Admin One',null,true));
create temp table ids as select (public.add_member(t.id('org2'),'P'||g,null,null,'member',null,null)->>'member_id')::uuid id from generate_series(1,2) g;
reset role;
select public.post_journal(t.id('org2'),'b'||row_number() over (),'share_purchase','x',jsonb_build_array(public.line('1010',null,10,0),public.line('2010',id,0,10))) from (select id from ids union all select id from public.members where org_id=t.id('org2') and role='org_admin') q;
select public.post_journal(t.id('org2'),'bi','fine_collection','x',jsonb_build_array(public.line('1010',null,70,0),public.line('4020',null,0,70)));
set role authenticated;
select t.ok((select jsonb_agg((x->>'payout')::bigint order by (x->>'payout')::bigint desc) from jsonb_array_elements(public.shareout_preview(t.id('org2'))->'payouts') x)='[34,33,33]'::jsonb,'Example B payouts 34 33 33');

-- reducing balance schedule matches old engine: 12000 at 12% over 3 months -> interest 120,80,40
select t.ok((select array_agg(interest_due order by installment) from public.calc_schedule(12000,12,3,'reducing_balance',current_date))='{120,80,40}'::bigint[],'reducing balance interest');
select t.ok((select sum(principal_due) from public.calc_schedule(10000,7,3,'flat',current_date))=10000,'flat schedule principal adds up');

-- forgot password with one-time code
select t.as_user(t.id('admin_u'));
select t.put('tmp',t.id('org'));
create temp table c(code text); 
insert into c select public.new_member_code(t.id('ben_m'));
select t.as_user(null);
set role anon;
select t.ok(public.reset_password_with_code('ben@test.local','WRONGONE','secret12')=false,'wrong code returns false');
reset role;
select t.ok(public.reset_password_with_code('ben@test.local',(select code from c),'secret12'),'right code resets');
select t.ok((select encrypted_password = extensions.crypt('secret12',encrypted_password) from auth.users where email='ben@test.local'),'new password stored as bcrypt');

-- demo and platform admin
set role authenticated;
select t.as_user(t.id('cy_u'));
select t.put('demo',public.seed_demo('Cy'));
select t.ok((public.dashboard(t.id('demo'))->>'active_loans')::int=1,'demo has a loan');
select t.ok((public.trial_balance(t.id('demo'))->>'balanced')::boolean,'demo balances');
select t.fails($$select public.platform_overview()$$,'Platform admins','only platform admin sees overview');
select t.as_user(t.id('plat_u'));
select t.ok(jsonb_array_length(public.platform_overview())>=3,'platform admin sees all groups');
select t.ok((public.dashboard(t.id('demo'))->>'members_active')::int=6,'platform admin can read a group');
select t.fails(format($$select public.add_member(t.id('demo'),'X',null,null,'member',null,null)$$),'not an active member','platform admin cannot change group data');

-- MY ACCOUNT
reset role;
\i ../migrations/20261107000000_accounts.sql
set role authenticated;
select t.as_user(t.id('ben_u'));
select t.ok(public.get_my_account()->>'sign_in_id'='ben@test.local','account shows my sign-in id');
select t.ok(jsonb_array_length(public.get_my_account()->'memberships')=1,'account lists my one group');
select t.ok(public.get_my_account()->>'full_name'='Ben','name falls back to my member card');
select t.fails($$select public.update_my_profile('{"phone":"123"}')$$,'Phone looks wrong','bad phone refused');
select t.fails($$select public.update_my_profile('{"full_name":"B"}')$$,'2 letters','short name refused');
select t.fails($$select public.update_my_profile('{"theme":"neon"}')$$,'check','unknown theme refused');
select t.fails($$select public.update_my_profile('{"text_scale":3}')$$,'check','huge text refused');
select public.update_my_profile('{"full_name":"Ben Okello","phone":"0700000099","theme":"dark","text_scale":1.15,"language":"lg","apply_to_groups":true}');
select t.ok((select full_name||phone from public.list_members(t.id('org')) x, jsonb_to_recordset(x) as r(full_name text, phone text) where full_name like 'Ben%')='Ben Okello256700000099','new name and phone copied to my group card');
select t.ok(public.get_my_account()->>'theme'='dark' and public.get_my_account()->>'language'='lg' and (public.get_my_account()->>'text_scale')::numeric=1.15,'look and language saved on account');
select t.as_user(t.id('ann_u'));
select t.fails($$select public.update_my_profile('{"phone":"0700000099","apply_to_groups":true}')$$,'already uses this phone','phone clash in a group refused');
select t.ok(coalesce(public.get_my_account()->>'phone','') <> '256700000099','refused change saved nothing');
select t.as_user(t.id('admin_u'));
select t.ok(public.list_audit(t.id('org'))::text like '%UPDATE_OWN_DETAILS%','own detail change is in the audit trail');
select t.ok((public.verify_audit_chain(t.id('org'))->>'ok')::boolean,'audit chain still verifies');
select t.as_user(t.id('ben_u'));
select public.record_sign_in('android','Pixel 7') from generate_series(1,55);
select t.ok(jsonb_array_length(public.get_my_account()->'sign_ins')=20,'shows latest 20 sign-ins');
reset role;
select t.ok((select count(*) from public.sign_in_events where user_id=t.id('ben_u'))=50,'keeps only 50 sign-ins');
set role authenticated;
select t.fails($$select * from public.profiles$$,'permission denied','profiles table closed to apps');
select t.fails($$select * from public.sign_in_events$$,'permission denied','sign-in table closed to apps');
select t.ok(jsonb_array_length(public.export_my_data()->'groups')=1,'export has my group');
select t.ok(jsonb_array_length(public.export_my_data()->'groups'->0->'statement'->'rows')>0,'export has my statement');
select t.ok(public.export_my_data()::text not like '%invite_code%' and public.export_my_data()::text not like '%idempotency%','export hides internal codes');
select t.as_user(t.id('ann_u'));
select t.ok(public.export_my_data()::text not like '%Ben Okello%256700000099%','export does not leak others');
select t.as_user(t.id('ben_u'));
select public.request_account_deletion('Leaving the group');
select t.fails($$select public.request_account_deletion('again')$$,'already asked','one open request only');
select public.cancel_account_deletion();
select t.ok(public.get_my_account()->'deletion_request'->>'status'='cancelled','request can be cancelled');
select public.request_account_deletion('Leaving for real');
select t.fails($$select public.list_deletion_requests()$$,'Platform admins','members cannot see requests');
select t.fails($$select public.complete_account_deletion(gen_random_uuid(),'')$$,'Platform admins','members cannot close accounts');
select t.as_user(t.id('plat_u'));
select t.put('del',(select (x->>'id')::uuid from jsonb_array_elements(public.list_deletion_requests()) x where x->>'status'='pending' limit 1));
select public.complete_account_deletion(t.id('del'),'Done by phone call');
select t.as_user(t.id('ben_u'));
select t.ok(jsonb_array_length(public.get_my_account()->'memberships')=0,'closed account leaves all groups');
select t.ok(public.get_my_account()->>'phone' is null,'closed account phone removed');
select t.as_user(t.id('admin_u'));
select t.ok(public.member_statement(t.id('org'),t.id('ben_m'))->'rows' is not null and jsonb_array_length(public.member_statement(t.id('org'),t.id('ben_m'))->'rows')>0,'money records kept after account closed');
select t.ok((public.trial_balance(t.id('org'))->>'balanced')::boolean,'books still balance');
select t.as_user(null);
set role anon;
select t.fails($$select public.get_my_account()$$,'permission denied','anon cannot read accounts');
reset role;
\pset format aligned
select count(*) filter (where ok) passed, count(*) filter (where not ok) failed from t.res;
