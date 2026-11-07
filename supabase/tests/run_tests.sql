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
\i ../migrations/20261107000100_hardening.sql
\i ../migrations/20261107000200_owner.sql
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

-- SAVINGS GOALS
reset role;
\i ../migrations/20261107000300_goals.sql
grant execute on function public.check_goal(uuid,uuid,text) to authenticated; -- test only, so t.fails can show its message
set role authenticated;
select t.as_user(t.id('ann_u'));
select t.fails($$select public.create_goal(t.id('org'),'X',100,null,null,'weekly',null)$$,'Your role','member cannot create a goal');
select t.as_user(t.id('treas_u'));
select t.put('goal', public.create_goal(t.id('org'),'School fees',30000,current_date,current_date+7,'daily',1000));
select t.as_user(t.id('admin_u'));
select t.put('goal2', public.create_goal(t.id('org2'),'Other group goal',100,null,null,'weekly',null));
select t.as_user(t.id('ann_u'));
select t.put('p1', (public.record_payment(t.id('org'),t.id('ann_m'),'savings',5000,'mtn_momo','GOAL001',null,null,null,'g1',t.id('goal'))->>'id')::uuid);
select t.ok((select goal_id from public.payment_records where id=t.id('p1'))=t.id('goal'),'payment carries the goal label');
select t.fails($$select public.record_payment(t.id('org'),t.id('ann_m'),'fine',100,'cash',null,null,null,'x','g2',t.id('goal'))$$,'Only shares or savings','fines cannot be for a goal');
select t.fails($$select public.record_payment(t.id('org'),t.id('ann_m'),'savings',100,'cash',null,null,null,null,'g3',t.id('goal2'))$$,'not open in this group','goal from another group refused');
select t.ok((public.list_goals(t.id('org'))->0->>'collected')::bigint=0 and (public.list_goals(t.id('org'))->0->>'pending')::bigint=5000,'unchecked money shows as pending, not collected');
select t.as_user(t.id('treas_u'));
select public.review_payment(t.id('p1'), true, 'seen');
select t.as_user(t.id('ann_u'));
select public.record_payment(t.id('org'),t.id('ann_m'),'savings',3000,'mtn_momo','PLAIN01',null,null,null,'g4');
select t.as_user(t.id('treas_u'));
select public.review_payment((select id from public.payment_records where idempotency_key='g4'), true, '');
select t.as_user(t.id('ann_u'));
select t.ok((public.list_goals(t.id('org'))->0->>'collected')::bigint=5000,'goal collected counts checked money');
select t.ok((public.list_goals(t.id('org'))->0->>'mine')::bigint=5000,'member sees own part');
select t.ok(public.list_goals(t.id('org'))->0->'by_member' = 'null'::jsonb,'member cannot see others parts');
select t.ok((public.savings_allocation(t.id('org'))->>'total')::bigint=8000,'savings total is the one account');
select t.ok((public.savings_allocation(t.id('org'))->>'for_goals')::bigint=5000 and (public.savings_allocation(t.id('org'))->>'not_for_goal')::bigint=3000,'split: 5000 for goal, 3000 not for a goal');
select t.fails(format($$select public.set_payment_goal(%L,%L,'x')$$,(select id from public.payment_records where idempotency_key='g4'),t.id('goal')),'Your role','member cannot relabel');
select t.as_user(t.id('admin_u'));
select t.ok(jsonb_array_length(public.list_goals(t.id('org'))->0->'by_member')>=1,'officer sees each member part');
select t.fails(format($$select public.set_payment_goal(%L,%L,'')$$,(select id from public.payment_records where idempotency_key='g4'),t.id('goal')),'Say why','relabel needs a reason');
select public.set_payment_goal((select id from public.payment_records where idempotency_key='g4'),t.id('goal'),'Ann said it was for school fees');
select t.ok((public.list_goals(t.id('org'))->0->>'collected')::bigint=8000,'relabelled money moves to the goal');
select t.ok(public.list_audit(t.id('org'))::text like '%CHANGE_GOAL_LABEL%no goal to School fees%','relabel is in the audit trail');
select t.ok((public.trial_balance(t.id('org'))->>'balanced')::boolean,'labels never unbalance the books');
select public.reverse_journal((select journal_id from public.payment_records where id=t.id('p1')),'Wrong amount');
select t.ok((public.list_goals(t.id('org'))->0->>'collected')::bigint=3000,'reversed money leaves the goal');
select t.ok((public.savings_allocation(t.id('org'))->>'for_goals')::bigint=3000 and (public.savings_allocation(t.id('org'))->>'total')::bigint=3000,'allocation follows the reversal');
select t.ok(jsonb_array_length(public.list_goals(t.id('org'))->0->'points')>=1,'goal has chart points');
select t.ok(jsonb_array_length(public.monthly_flows(t.id('org')))=12,'chart has 12 months');
select t.ok((public.monthly_flows(t.id('org'))->11->>'paid_in')::bigint>0,'this month shows money in');
select t.ok((select bool_and((x->>'paid_in')::bigint>=0) from jsonb_array_elements(public.monthly_flows(t.id('org'))) x),'no negative months');
select t.as_user(t.id('ann_u'));
select t.ok((public.monthly_flows(t.id('org'))->11->>'savings')::bigint=3000,'member chart shows own savings only');
select t.as_user(t.id('stranger_u'));
select t.fails($$select public.list_goals(t.id('org'))$$,'not a member','stranger cannot see goals');
select t.as_user(t.id('treas_u'));
select public.close_goal(t.id('goal'));
select t.as_user(t.id('ann_u'));
select t.fails($$select public.record_payment(t.id('org'),t.id('ann_m'),'savings',100,'cash',null,null,null,null,'g9',t.id('goal'))$$,'not open','closed goal takes no new money');
-- ONLINE PAYMENTS: the gateway confirms, the server re-checks, then it posts
reset role;
\i ../migrations/20261107000400_online_payments.sql
-- Same as Supabase: the server role can read every table and skips row rules.
grant usage on schema public, t to service_role; grant all on all tables in schema public to service_role; alter role service_role bypassrls;
grant execute on all functions in schema t to service_role;
grant all on t.v, t.res to service_role; grant all on sequence t.res_n_seq to service_role;
create table t.n(k text primary key, v bigint); grant all on t.n to authenticated, service_role;
set role authenticated;
select t.as_user(t.id('ann_u'));
select t.fails($$select public.create_gateway_payment(t.id('org'),t.id('ann_m'),'savings',5000,null,null,null)$$,'not switched on','no gateway, no online payment');
select t.ok((public.gateway_status(t.id('org'))->>'enabled')::boolean = false,'member sees online pay is off');
select t.fails($$select * from public.gateway_accounts$$,'permission denied','apps cannot read gateway keys');
reset role; set role service_role;
select t.fails(format($$select public.save_gateway_account(%L,%L,'flutterwave','test','1234','ENC',null)$$, t.id('org'), t.id('ann_u')),'Only the group admin','member cannot connect a gateway');
select t.fails(format($$select public.save_gateway_account(%L,%L,'flutterwave','test','1234','ENC',null)$$, t.id('org'), t.id('treas_u')),'demo group','test keys refused on a real group');
select public.save_gateway_account(t.id('org'), t.id('treas_u'),'flutterwave','live','1234','ENC',null);
reset role; set role authenticated;
select t.as_user(t.id('ann_u'));
select t.fails(format($$select public.save_gateway_account(%L,%L,'flutterwave','test','1234','ENC',null)$$, t.id('org'), t.id('treas_u')),'permission denied','app cannot save keys directly');
select t.ok(public.gateway_status(t.id('org'))->>'gateway'='flutterwave' and public.gateway_status(t.id('org'))->>'key_hint' is null,'member sees gateway on, but no key hint');
select t.fails($$select public.create_gateway_payment(t.id('org'),t.id('cy_m'),'savings',5000,null,null,null)$$,'only pay for yourself','member cannot start a payment for another');
select t.fails($$select public.create_gateway_payment(t.id('org'),t.id('ann_m'),'withdrawal',5000,null,null,null)$$,'coming in','money out cannot go online');
select t.put('gp1', (public.create_gateway_payment(t.id('org'),t.id('ann_m'),'savings',5000,null,null,null)->>'id')::uuid);
select t.ok((select tx_ref like 'SL-%' and length(tx_ref)=35 from public.gateway_payments where id=t.id('gp1')),'server makes the reference');
select t.fails(format($$select public.settle_gateway_payment(%L,true,'FLW1','MP9',5000,'UGX','mobilemoneyuganda',null)$$,t.id('gp1')),'permission denied','app cannot mark itself paid');
select t.as_user(t.id('cy_u'));
select t.ok(jsonb_array_length(public.list_gateway_payments(t.id('org')))=0,'member cannot see another member online payments');
reset role;
select t.ok(not public.can_see_gateway_payment(t.id('gp1'), t.id('cy_u')) and public.can_see_gateway_payment(t.id('gp1'), t.id('ann_u')) and public.can_see_gateway_payment(t.id('gp1'), t.id('treas_u')),'only owner and officers may check a payment');
insert into t.n select 'momo0', t.bal(t.id('org'),'1020');
set role service_role;
select public.gateway_payment_started(t.id('gp1'),'https://checkout.example/x',null);
select public.settle_gateway_payment(t.id('gp1'),true,'FLW1','MP9',5000,'UGX','mobilemoneyuganda',null);
reset role;
select t.ok((select status from public.gateway_payments where id=t.id('gp1'))='paid','verified payment is paid');
select t.ok(t.bal(t.id('org'),'1020') = (select v from t.n where k='momo0') + 5000,'verified payment posts at once, no human typing');
select t.ok((select p.status='confirmed' and p.external_ref='FLW1' and p.channel='flutterwave' from public.payment_records p where p.id=(select payment_id from public.gateway_payments where id=t.id('gp1'))),'record carries the gateway transaction id');
select t.ok(exists(select 1 from public.audit_log where org_id=t.id('org') and action='ONLINE_PAYMENT_VERIFIED' and details like '%txn FLW1%'),'verification is in the audit trail');
set role service_role;
select t.ok((public.settle_gateway_payment(t.id('gp1'),true,'FLW1','MP9',5000,'UGX','x',null)->>'status')='paid','a second notice changes nothing');
reset role;
select t.ok(t.bal(t.id('org'),'1020') = (select v from t.n where k='momo0') + 5000,'no double posting');
-- Paid the wrong amount: kept, but a person must check
set role authenticated; select t.as_user(t.id('ann_u'));
select t.put('gp2', (public.create_gateway_payment(t.id('org'),t.id('ann_m'),'savings',8000,null,null,null)->>'id')::uuid);
select t.put('gp3', (public.create_gateway_payment(t.id('org'),t.id('ann_m'),'savings',8000,null,null,null)->>'id')::uuid);
select t.put('gp4', (public.create_gateway_payment(t.id('org'),t.id('ann_m'),'savings',8000,null,null,null)->>'id')::uuid);
reset role; set role service_role;
select public.settle_gateway_payment(t.id('gp2'),true,'FLW2',null,800,'UGX','card',null);
select public.settle_gateway_payment(t.id('gp3'),true,'flw1',null,8000,'UGX','card',null);
select public.settle_gateway_payment(t.id('gp4'),false,null,null,null,null,null,'Customer cancelled');
reset role;
select t.ok((select status from public.gateway_payments where id=t.id('gp2'))='needs_review','underpaid goes to a person');
select t.ok((select p.status from public.payment_records p where p.id=(select payment_id from public.gateway_payments where id=t.id('gp2')))='pending','underpaid record waits in Approvals');
select t.ok((select status from public.gateway_payments where id=t.id('gp3'))='needs_review' and (select payment_id from public.gateway_payments where id=t.id('gp3')) is null,'same gateway id cannot be used twice');
select t.ok((select status from public.gateway_payments where id=t.id('gp4'))='failed' and (select payment_id from public.gateway_payments where id=t.id('gp4')) is null,'failed payment makes no record');
select t.ok(t.bal(t.id('org'),'1020') = (select v from t.n where k='momo0') + 5000,'only the verified right amount posted');
select t.as_user(t.id('treas_u'));
select t.ok((public.trial_balance(t.id('org'))->>'balanced')::boolean,'books still balance');
set role authenticated; select t.as_user(t.id('treas_u'));
select public.review_payment((select payment_id from public.gateway_payments where id=t.id('gp2')), true, 'Checked: 800 paid');
select t.ok(t.bal(t.id('org'),'1020') = (select v from t.n where k='momo0') + 5800,'officer can confirm the underpaid one');
select t.put('gp5', (public.create_gateway_payment(t.id('org'),t.id('cy_m'),'savings',1000,null,null,null)->>'id')::uuid);
select t.ok(t.id('gp5') is not null,'officer can start a payment for a member');
select t.as_user(t.id('ann_u'));
select t.fails($$select public.disable_gateway(t.id('org'))$$,'Your role','member cannot switch off online pay');
select t.as_user(t.id('stranger_u'));
select t.fails($$select public.list_gateway_payments(t.id('org'))$$,'not a member','stranger sees nothing');
select t.as_user(t.id('treas_u'));
select public.disable_gateway(t.id('org'));
select t.fails($$select public.create_gateway_payment(t.id('org'),t.id('cy_m'),'savings',1000,null,null,null)$$,'not switched on','switched off means no new online payments');

-- PLATFORM ADMINISTRATORS
reset role;
insert into auth.users(id,email) values (gen_random_uuid(),'danmclaston@gmail.com');
select t.put('owner_u', (select id from auth.users where email='danmclaston@gmail.com'));
set role authenticated;
select t.as_user(t.id('plat_u'));
select t.fails($$select public.add_platform_admin('x@y.com')$$,'Only the platform owner','admin cannot add admins');
select t.ok(jsonb_array_length(public.list_platform_admins()->'admins')=2,'admin sees the admin list');
select t.as_user(t.id('ann_u'));
select t.fails($$select public.list_platform_admins()$$,'Platform admins only','member cannot see admin list');
select t.fails($$select public.search_users('test')$$,'Platform admins only','member cannot search users');
select t.as_user(t.id('owner_u'));
select t.ok((public.list_platform_admins()->>'me_owner')::boolean,'owner email becomes owner');
select t.ok(jsonb_array_length(public.search_users('ben'))=1,'owner finds a signed-up user');
select t.fails($$select public.search_users('b')$$,'2 letters','search needs 2 letters');
select t.ok(public.add_platform_admin(' Ben@Test.local ')->>'status'='added','owner adds signed-up user by email');
select t.as_user(t.id('ben_u')); select t.ok(public.is_platform_admin(),'new admin is admin');
select t.as_user(t.id('owner_u'));
select t.fails($$select public.add_platform_admin('ben@test.local')$$,'already','cannot add twice');
select t.fails($$select public.add_platform_admin('not-an-email')$$,'valid email','bad email refused');
select t.ok(public.add_platform_admin('newdev@test.local')->>'status'='invited','unknown email becomes an invite');
reset role;
insert into auth.users(id,email) values (gen_random_uuid(),'NewDev@test.local');
select t.ok(exists(select 1 from public.platform_admins a join auth.users u on u.id=a.user_id where u.email='NewDev@test.local' and a.role='admin'),'invited person is admin on sign-up');
select t.ok(not exists(select 1 from public.platform_admin_invites),'invite used up');
set role authenticated; select t.as_user(t.id('owner_u'));
select public.remove_platform_admin(t.id('ben_u'));
select t.as_user(t.id('ben_u')); select t.ok(not public.is_platform_admin(),'removed admin loses access');
select t.as_user(t.id('owner_u'));
select t.fails(format($$select public.remove_platform_admin(%L)$$,t.id('owner_u')),'owner cannot','owner cannot be removed');
select public.add_platform_admin('later@test.local'); select public.cancel_admin_invite('later@test.local');
select t.ok(jsonb_array_length(public.list_platform_admins()->'invites')=0,'owner can cancel an invite');
reset role;
select t.fails($$update public.platform_audit set details='x'$$,'permanent','admin history cannot be edited');
select t.ok((select count(*) from public.platform_audit)>=6,'admin changes are in the history');
-- COUNTRIES AND PREFERENCES
reset role;
\i ../migrations/20261107000500_countries_prefs.sql
select t.ok((select country_code from public.organizations where id=t.id('org'))='UG','existing UGX group is Uganda');
set role authenticated; select t.as_user(t.id('treas_u'));
select t.fails($$select public.set_org_country(t.id('org'),'KE')$$,'Your role','treasurer cannot change country');
select t.as_user(t.id('admin_u'));
select public.set_org_country(t.id('org'),'KE');
select t.ok((select country_code from public.organizations where id=t.id('org'))='KE','admin sets the country');
select t.fails($$select public.set_org_country(t.id('org'),'XX')$$,'Choose Uganda','unknown country refused');
select public.set_org_country(t.id('org'),'UG');
select public.update_my_prefs('{"country":"TZ","show_tips":false}');
select public.update_my_prefs('{"tour_done":true,"evil":"x"}');
select t.ok(public.get_my_account()->'prefs' = '{"country":"TZ","show_tips":false,"tour_done":true}'::jsonb,'preferences saved, unknown keys ignored');
select t.fails($$select public.update_my_prefs('{"country":"ZZ"}')$$,'Unknown country','bad country preference refused');
-- LOAN RULES: interest modes, free months, pay-at-end, late fees, waivers
reset role;
create table t.before as select id, public.loan_remaining(id) as rem, public.loan_arrears_days(id) as arr from public.loans;
\i ../migrations/20261107000600_loan_rules.sql
select t.ok(not exists(select 1 from t.before b where public.loan_remaining(b.id) <> b.rem or public.loan_arrears_days(b.id) <> b.arr),'old loans unchanged');
-- The maths, one rule at a time (12000 over 3 months)
select t.ok((select array_agg(total_due order by installment) from public.calc_schedule2(12000,5,'monthly','flat',3,1,'monthly','2026-01-31')) = array[4000,4600,4600]::bigint[],'5% a month flat, first month free');
select t.ok((select array_agg(interest_due order by installment) from public.calc_schedule2(12000,5,'monthly','reducing_balance',3,1,'monthly','2026-01-31')) = array[0,400,200]::bigint[],'5% a month reducing, first month free');
select t.ok((select array_agg(total_due) from public.calc_schedule2(12000,5,'monthly','flat',3,1,'end','2026-01-31')) = array[13200]::bigint[],'pay everything at the end');
select t.ok((select due_date from public.calc_schedule2(12000,5,'monthly','flat',3,1,'end','2026-01-31'))='2026-04-30','end date is 3 calendar months later');
select t.ok((select array_agg(interest_due order by installment) from public.calc_schedule2(12000,10,'once','flat',3,0,'monthly','2026-01-31')) = array[400,400,400]::bigint[],'one-time 10% spread over the months');
select t.ok((select sum(interest_due) from public.calc_schedule2(12000,0,'none','flat',3,2,'monthly','2026-01-31'))=0,'no interest means no interest');
select t.ok((select sum(interest_due) from public.calc_schedule2(12000,12,'yearly','flat',3,0,'monthly','2026-01-31'))=360,'12% a year for 3 months is 360');
select t.ok((select sum(interest_due) from public.calc_schedule2(12000,10,'yearly','flat',1,0,'monthly','2026-01-31'))=100,'10% a year for 1 month is exactly 100, no rounding slip');
select t.ok((select sum(interest_due) from public.calc_schedule2(10000,2.5,'monthly','reducing_balance',4,0,'monthly','2026-01-31'))=624,'2.5% a month reducing on 10000 for 4 months: 250+187+125+62');
select t.ok((select sum(principal_due) from public.calc_schedule2(10001,5,'monthly','reducing_balance',3,0,'monthly','2026-01-31'))=10001,'every shilling of the loan is scheduled');
select t.ok(public.late_fee_for(4000,17,'percent',0,10,'week',3)=800,'10% of missed payment each week after 3 grace days: 17 days late is 2 weeks');
select t.ok(public.late_fee_for(4000,3,'percent',0,10,'week',3)=0,'no fee inside the grace days');
select t.ok(public.late_fee_for(4000,10,'fixed',500,0,'day',0)=5000,'fixed 500 a day for 10 days');
select t.ok(public.late_fee_for(4000,40,'fixed',1000,0,'once',0)=1000,'fixed once is charged once');
select t.ok(public.late_fee_for(4000,31,'percent',0,5,'month',0)=400,'5% a month: 31 days is 2 months');
-- Group rules
set role authenticated;
select t.as_user(t.id('officer_u'));
select t.fails($$select public.set_loan_rules(t.id('org'),'{"interest_mode":"none"}')$$,'Your role','loan officer cannot change group loan rules');
select t.as_user(t.id('admin_u'));
select t.fails($$select public.set_loan_rules(t.id('org'),'{"interest_rate":150}')$$,'between 0 and 100','interest above 100% refused');
select t.fails($$select public.set_loan_rules(t.id('org'),'{"late_fee_every":"hour"}')$$,'how often','unknown late fee period refused');
select public.set_loan_rules(t.id('org'),'{"interest_mode":"monthly","interest_rate":5,"calculation":"flat","free_months":1,"repayment_plan":"monthly","late_fee_type":"percent","late_fee_pct":10,"late_fee_every":"week","late_fee_grace_days":3,"late_fee_cap_pct":50}');
select t.ok((public.preview_loan(t.id('org'),12000,3,null)->'schedule'->1->>'total_due')::bigint=4600,'preview uses group rules');
select t.ok((public.preview_loan(t.id('org'),12000,3,'{"repayment_plan":"end"}')->'schedule'->0->>'total_due')::bigint=13200,'preview can try other rules');
select t.as_user(t.id('ann_u'));
select t.fails(format($$select public.apply_loan2(t.id('org'),%L,12000,3,'{"interest_mode":"none"}','x')$$,t.id('ann_m')),'Only the group admin or loan officer','member cannot give herself no interest');
select t.put('ln2', public.apply_loan2(t.id('org'),t.id('ann_m'),12000,3,null,'Shop stock'));
select t.ok((select total_interest=1200 and schedule_version=2 and late_fee_type='percent' and free_months=1 from public.loans where id=t.id('ln2')),'loan copies the group rules');
select t.as_user(t.id('officer_u'));
select public.approve_loan(t.id('ln2'),'R9',t.id('sec_m'),t.id('cy_m'));
select t.as_user(t.id('treas_u'));
select public.record_payment(t.id('org'), t.id('cy_m'),'savings',20000,'cash',null,null,null,null,'cs1');
select t.as_user(t.id('admin_u'));
select public.review_payment((select (x->>'id')::uuid from jsonb_array_elements(public.list_payments(t.id('org'),'pending')) x limit 1), true, '');
select t.as_user(t.id('treas_u'));
select public.disburse_loan(t.id('ln2'),'cash',null);
-- Pretend it was paid out long enough ago that payment 1 is 17 days late
reset role;
update public.loans set disbursed_at = (current_date - 17 - interval '1 month') where id = t.id('ln2');
select t.ok((select due_date from public.loan_sched(t.id('ln2')) where installment=1) = current_date - 17,'first payment was due 17 days ago');
select t.ok((public.loan_late_fees(t.id('ln2'))->>'total')::bigint=800,'late fee: 10% of 4000, 2 weeks');
select t.ok(public.loan_remaining(t.id('ln2'))=14000,'owed now: 12000 + 1200 interest + 800 late fee');
select t.ok(public.loan_arrears_days(t.id('ln2'))=17,'17 days in arrears');
set role authenticated;
select t.as_user(t.id('ann_u'));
select t.ok((public.loan_late_fee_report(t.id('ln2'))->>'due')::bigint=800,'borrower sees her late fee');
select t.fails(format($$select public.waive_late_fees(%L,100,'please')$$,t.id('ln2')),'Your role','borrower cannot forgive her own fee');
select t.as_user(t.id('treas_u'));
select t.fails(format($$select public.waive_late_fees(%L,900,'too much')$$,t.id('ln2')),'up to 800','cannot forgive more than is owed');
select public.waive_late_fees(t.id('ln2'),300,'Sick child, agreed in meeting');
reset role;
select t.ok(public.loan_remaining(t.id('ln2'))=13700,'forgiven 300');
insert into t.n select 'fees0', t.bal(t.id('org'),'4020'); insert into t.n select 'int0', t.bal(t.id('org'),'4010');
set role authenticated; select t.as_user(t.id('treas_u'));
select public.record_payment(t.id('org'), t.id('ann_m'),'loan_repayment',600,'cash',null,null,t.id('ln2'),null,'lr1');
select t.as_user(t.id('admin_u'));
select public.review_payment((select (x->>'id')::uuid from jsonb_array_elements(public.list_payments(t.id('org'),'pending')) x limit 1), true, '');
reset role;
select t.ok(t.bal(t.id('org'),'4020') = (select v from t.n where k='fees0') - 500,'late fee paid first (500 to fees income)');
select t.ok(t.bal(t.id('org'),'4010') = (select v from t.n where k='int0') - 100,'then interest (100)');
select t.ok(public.loan_fees_due(t.id('ln2'))=0,'no late fee left');
-- Pay enough to cover payment 1: the late fee stops growing
set role authenticated; select t.as_user(t.id('treas_u'));
select public.record_payment(t.id('org'), t.id('ann_m'),'loan_repayment',3900,'cash',null,null,t.id('ln2'),null,'lr2');
select t.as_user(t.id('admin_u'));
select public.review_payment((select (x->>'id')::uuid from jsonb_array_elements(public.list_payments(t.id('org'),'pending')) x limit 1), true, '');
reset role;
select t.ok((public.loan_late_fees(t.id('ln2'))->'rows'->0->>'paid_on')::date = current_date,'payment 1 marked paid today');
select t.ok(public.loan_arrears_days(t.id('ln2'))=0,'no longer in arrears');
select t.ok(public.loan_remaining(t.id('ln2'))=13700-600-3900,'balance after two payments');
select t.ok((public.trial_balance(t.id('org'))->>'balanced')::boolean,'books balance with late fees');
-- Cap: fees never pass the limit
update public.loans set late_fee_cap_pct = 5 where id = t.id('ln2');
update public.loans set disbursed_at = (current_date - 200 - interval '1 month') where id = t.id('ln2');
select t.ok((public.loan_late_fees(t.id('ln2'))->>'total')::bigint <= 600 and (public.loan_late_fees(t.id('ln2'))->>'capped')::boolean,'late fees stop at the limit (5% of 12000)');
select t.fails($$update public.loan_fee_waivers set amount=1$$,'permanent','forgiven fees cannot be edited');
reset role;
