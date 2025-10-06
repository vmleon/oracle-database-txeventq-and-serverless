-- Drop existing queue (if exists)
begin
   dbms_aqadm.stop_queue(queue_name => 'REPORT_QUEUE');
   dbms_aqadm.drop_queue(queue_name => 'REPORT_QUEUE');
   dbms_aqadm.drop_queue_table(queue_table => 'REPORT_QUEUE_TABLE');
exception
   when others then
      null;
end;
/

-- Create TxEventQ queue
begin
   dbms_aqadm.create_transactional_event_queue(
      queue_name         => 'REPORT_QUEUE',
      queue_payload_type => 'JSON',
      multiple_consumers => false,
      storage_clause     => null,
      comment            => 'Queue for report generation requests'
   );
end;
/

-- Start queue
begin
   dbms_aqadm.start_queue(queue_name => 'REPORT_QUEUE');
end;
/

-- Verify queue
select queue_name, queue_table
  from user_queue_tables
 where queue_name = 'REPORT_QUEUE';

exit;