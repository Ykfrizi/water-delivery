enum UserRole {
  customer,
  vendor,
  admin,
}

extension UserRoleX on UserRole {
  String get displayName => switch (this) {
        UserRole.customer => 'Customer',
        UserRole.vendor => 'Vendor',
        UserRole.admin => 'Admin',
      };

  String get shortLabel => switch (this) {
        UserRole.customer => 'Shop & order water',
        UserRole.vendor => 'Manage your store',
        UserRole.admin => 'Operations dashboard',
      };

  bool get canRegister => this != UserRole.admin;

  /// Shown on the welcome screen. Admin signs in from Customer or Vendor.
  static const List<UserRole> welcomeRoles = [
    UserRole.customer,
    UserRole.vendor,
  ];
}
