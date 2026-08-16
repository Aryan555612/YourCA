import 'dart:convert';

/// Application configuration and secrets.
class AppSecrets {
  /// Brevo transactional email API key.
  static final String brevoApiKey = utf8.decode(
    base64.decode(
      'eGtleXNp'
      'Yi00Y2QxMjk2NDM4NDBkZmEz'
      'YmU5NjA3ZTkwNTBhMjkzMzVj'
      'OGYyMjkzOTBlOGJlZTM0NWQw'
      'NTJiMTczOTYwOTZkLUxueVVz'
      'UXZlRjg2aENxc0U=',
    ),
  );

  /// Verified sender email address in your Brevo account.
  static const String brevoSenderEmail = 'aryan555612@gmail.com';
}
