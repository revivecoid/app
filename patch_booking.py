import re
file_path = "lib/features/customer_app/order/presentation/booking_scheduling_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

replacement = """      // 3. Advance status 2_estimated → 3_booked via RPC (validates transition)
      await _sb.rpc('advance_job_status', params: {
        'p_job_id': widget.jobId,
        'p_new_status': '3_booked',
      });

      // 4. Try Auto-Assign Engine
      try {
        final res = await _sb.rpc('execute_auto_assign', params: {'p_job_id': widget.jobId});
        debugPrint('[AutoAssign] Result: $res');
      } catch (e) {
        debugPrint('[AutoAssign] Engine disabled or no eligible partner (non-fatal): $e');
      }"""

content = content.replace("""      // 3. Advance status 2_estimated → 3_booked via RPC (validates transition)
      await _sb.rpc('advance_job_status', params: {
        'p_job_id': widget.jobId,
        'p_new_status': '3_booked',
      });""", replacement)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
print("Booking patched.")
