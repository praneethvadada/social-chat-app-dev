class UserSearch {
  final int userId;
  final String username;
  final String fullName;

  const UserSearch({required this.userId, required this.username, required this.fullName});

  String get initials {
    final parts = fullName.split(' ');
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

const mockUsers = <UserSearch>[
  UserSearch(userId: 2, username: '@sarah_wilson', fullName: 'Sarah Wilson'),
  UserSearch(userId: 3, username: '@mike_j', fullName: 'Mike Johnson'),
  UserSearch(userId: 4, username: '@emma_davis', fullName: 'Emma Davis'),
  UserSearch(userId: 5, username: '@olivia_b', fullName: 'Olivia Brown'),
  UserSearch(userId: 6, username: '@noah_s', fullName: 'Noah Smith'),
  UserSearch(userId: 7, username: '@liam_r', fullName: 'Liam Roberts'),
];
