-- Enqueue test messages
declare
   enqueue_options    dbms_aq.enqueue_options_t;
   message_properties dbms_aq.message_properties_t;
   message_handle     raw(16);
   message            json;
begin
    -- Message 1
   message :=
      json(
         '{"title": "Monthly Sales Report", "content": "Sales data for January 2025...", "date": "2025-01-15T10:30:00Z"}'
      );
   dbms_aq.enqueue(
      queue_name         => 'REPORT_QUEUE',
      enqueue_options    => enqueue_options,
      message_properties => message_properties,
      payload            => message,
      msgid              => message_handle
   );

    -- Message 2
   message :=
      json(
         '{"title": "Quarterly Financial Summary", "content": "Q4 2024 financial summary...", "date": "2025-01-20T14:00:00Z"}'
      );
   dbms_aq.enqueue(
      queue_name         => 'REPORT_QUEUE',
      enqueue_options    => enqueue_options,
      message_properties => message_properties,
      payload            => message,
      msgid              => message_handle
   );

   commit;
   dbms_output.put_line('Enqueued 2 test messages');
end;
/
exit;