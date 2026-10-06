class AppErrorHandler {
  static String getFriendlyError(dynamic e) {
    final errorMsg = e.toString().toLowerCase();

    if (errorMsg.contains('statement timeout') ||
        errorMsg.contains('57014') ||
        errorMsg.contains('canceling statement') ||
        errorMsg.contains('cancelling statement')) {
      return 'This is taking longer than usual. Please try again in a moment.';
    }

    if (errorMsg.contains('clientexception') ||
        errorMsg.contains('connection abort') ||
        errorMsg.contains('socketexception') ||
        errorMsg.contains('failed host lookup') ||
        errorMsg.contains('network') ||
        errorMsg.contains('timed out') ||
        errorMsg.contains('timeout')) {
      return 'Network connection lost. Please check your internet and try again.';
    }

    if (errorMsg.contains('failed to fetch') || errorMsg.contains('postgrestexception')) {
      return 'Could not load data right now. Please try again.';
    }

    if (errorMsg.contains('authexception') || errorMsg.contains('jwt')) {
      return 'Your session expired. Please sign in again.';
    }

    // Never show raw exception text to users.
    return 'Something went wrong. Please try again.';
  }
}
