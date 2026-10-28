import 'package:supabase_flutter/supabase_flutter.dart';

bool definitiveOperationError(Object error) =>
    error is PostgrestException &&
    ([
          'P0001',
          'P0002',
          '42501',
          '40001',
          'PGRST202',
          'PGRST203',
          'PGRST204',
          'PGRST301',
          'PGRST302',
        ].contains(error.code) ||
        error.code?.startsWith('23') == true ||
        error.code?.startsWith('22') == true);

String operationErrorMessage(Object error) {
  if (error is PostgrestException) {
    switch (error.code) {
      case '23P01':
        return 'This member already has a membership covering those dates. Use Renew membership to start after the current membership ends.';
      case '40001':
        return 'This record changed on another device. Close this window, sync, and try again.';
      case 'PGRST202':
      case 'PGRST203':
      case 'PGRST204':
        return 'This action needs a database update. Ask the app administrator to apply the latest migrations.';
      case 'PGRST301':
      case 'PGRST302':
        return 'Your session has expired. Sign in again before continuing.';
      case '23503':
        return 'A related member or package is unavailable. Sync your workspace and select it again.';
      case '23505':
        return 'This record already exists. Sync your workspace to see the saved record.';
      case '42501':
        return error.message == 'insufficient_privilege'
            ? 'Your role does not have permission for this action.'
            : error.message;
      case 'P0001':
        return error.message;
      case 'P0002':
        return 'The selected record is no longer available. Sync and select it again.';
    }
  }
  if (error is StateError) return error.message.toString();
  if (error is FunctionException) {
    return error.status == 404
        ? 'Employee invitations are not available yet. Ask the app administrator to deploy the invitation service.'
        : 'The invitation could not be sent. Check the email address or try again later.';
  }
  return 'No confirmation was received. Check your connection and retry here; the same request will be reused safely.';
}
