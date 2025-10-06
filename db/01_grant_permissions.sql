-- Grant permissions to PDBADMIN for Advanced Queuing
grant execute on dbms_aqadm to pdbadmin;
grant aq_administrator_role to pdbadmin;
alter user pdbadmin quota unlimited on users;

exit;