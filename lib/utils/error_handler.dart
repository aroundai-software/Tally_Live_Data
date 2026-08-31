class AppErrorHandler {
  static String getFriendlyError(dynamic e) {
    String errorMsg = e.toString();
    
    if (errorMsg.contains('ClientException') || 
        errorMsg.contains('connection abort') || 
        errorMsg.contains('SocketException') ||
        errorMsg.contains('Failed host lookup')) {
      return 'Network connection lost. Please check your internet connection and try again.';
    }
    
    if (errorMsg.contains('Failed to fetch') || errorMsg.contains('PostgrestException')) {
      return 'Failed to load data. Please try again.';
    }

    // You can add more generic database or auth errors here
    if (errorMsg.contains('AuthException')) {
      return 'Authentication failed. Please login again.';
    }

    return errorMsg;
  }
}
