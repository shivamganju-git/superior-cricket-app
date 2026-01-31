/// YouTube API Configuration
/// 
/// IMPORTANT: Replace 'YOUR_YOUTUBE_API_KEY' with your actual YouTube Data API v3 key
/// 
/// To get your API key:
/// 1. Go to https://console.cloud.google.com/
/// 2. Create a new project or select an existing one
/// 3. Enable YouTube Data API v3
/// 4. Go to Credentials → Create Credentials → API Key
/// 5. Copy the API key and replace it below
/// 
/// For production, consider storing this in environment variables or secure storage
class YouTubeConfig {
  // Replace with your YouTube Data API v3 key
  static const String apiKey = 'AIzaSyDRv8LLeQvOo1OGp0vr6hUSKfUY0PEzJuY';
  
  // Default channel handle for PITCH POINT
  static const String defaultChannelHandle = '@PITCH-POINT';
  
  // YouTube IFrame Player base URL
  static const String embedBaseUrl = 'https://www.youtube.com/embed/';
  
  // YouTube Data API v3 base URL
  static const String apiBaseUrl = 'https://www.googleapis.com/youtube/v3';

  // OAuth 2.0 Client Credentials (REQUIRED for token refresh)
  // Get these from Google Cloud Console → Credentials → OAuth 2.0 Client IDs
  static const String clientId = '17659429390-n9gubiec2mvpst2ji3gn4i5hv7brh6it.apps.googleusercontent.com';
  static const String clientSecret = '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';
}

