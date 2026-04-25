class LoginRequest {
  final String email;
  final String password;
  const LoginRequest({required this.email, required this.password});
  Map<String, dynamic> toJson() => {'email': email, 'password': password};
}

class RegisterRequest {
  final String username;
  final String email;
  final String password;
  final String role;
  const RegisterRequest({
    required this.username,
    required this.email,
    required this.password,
    this.role = 'CLIENT',
  });
  Map<String, dynamic> toJson() => {
        'username': username,
        'email': email,
        'password': password,
        'role': role,
      };
}

class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final String userId;
  final String username;
  final String email;
  final String role;
  final String? departmentId;
  final int expiresIn;

  const AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.username,
    required this.email,
    required this.role,
    this.departmentId,
    required this.expiresIn,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        departmentId: json['departmentId'] as String?,
        expiresIn: json['expiresIn'] as int,
      );
}
