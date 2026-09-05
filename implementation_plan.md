# Add Password Reset Flow

The user requested a password reset module for when users forget their passwords.

## Proposed Changes

### 1. `lib/app_router.dart` (Login Screen)
- **Forgot Password UI**: Add a "Forgot Password?" text button near the login fields.
- **Toggle State**: Add a `_isResettingPassword` boolean state.
- **Reset Logic**: When `_isResettingPassword` is true, the UI will change to show only the Email field and a "SEND RESET LINK" button.
- **Action**: Calling `Supabase.instance.client.auth.resetPasswordForEmail(email, redirectTo: '.../auth/callback')` will send the user a recovery email.

### 2. `lib/app_router.dart` (Auth Callback & Routing)
- When a user clicks a password recovery link, Supabase fires an `AuthChangeEvent.passwordRecovery` event.
- We will update the `SupabaseAuthRefreshNotifier` to capture this event.
- We will add a global provider `passwordRecoveryEventProvider` to track if a recovery is pending.
- We will add a new GoRoute: `/update-password`.

### 3. `lib/features/customer_app/profile/presentation/update_password_screen.dart` [NEW]
- Create a new screen where users can enter a new password.
- **Action**: Calls `Supabase.instance.client.auth.updateUser(UserAttributes(password: newPassword))` to save the new password.
- After success, it clears the recovery flag and redirects the user to `/` (Home).

### 4. `lib/app_router.dart` (Router Guard)
- If `passwordRecoveryEventProvider` is true, the router will force a redirect to `/update-password` until the password is successfully changed.

## Verification Plan
1. Launch app, go to `/login`.
2. Click "Forgot Password?", enter an email, click "SEND RESET LINK".
3. Verify the success message appears.
4. (Simulated) Click the link in the email, hit `/auth/callback`, verify the app routes to `/update-password`.
5. Enter a new password, submit, and verify it redirects back to the dashboard.
