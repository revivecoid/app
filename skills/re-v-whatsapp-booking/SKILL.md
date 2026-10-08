---
name: re-v-whatsapp-booking
description: Use when customer books via WhatsApp. Executes the pipeline.
---

# Re-V WhatsApp Booking

When a customer sends photos and wants to book a repair via the Re-V WhatsApp chatbot:
1. Save the photos they sent to the local disk.
2. Ask for their name and phone number if not available from context.
3. **Generate an OTP** for their number and send it to them in chat:
   `python scripts/whatsapp_booking_pipeline.py --action request-otp --phone "08123456789"`
4. Wait for them to reply with the code. Verify it:
   `python scripts/whatsapp_booking_pipeline.py --action verify-otp --phone "08123456789" --code "123456"`
5. Once verified, run the automated booking pipeline to map the number, estimate cost, assign a workshop, and create the job:
   `python scripts/whatsapp_booking_pipeline.py --action book --phone "08123456789" --name "Budi" --photos "C:/path/to/img1.jpg"`

Tell the user their Job ID and estimated cost once the pipeline completes.