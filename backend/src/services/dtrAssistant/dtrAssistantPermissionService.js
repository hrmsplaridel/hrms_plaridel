function getEmployeeSelfScope(user) {
  const userId = user?.id;
  if (!userId) {
    const err = new Error('Not authenticated');
    err.statusCode = 401;
    throw err;
  }

  return {
    mode: 'employee_self',
    userId,
    role: user.role || 'employee',
  };
}

module.exports = { getEmployeeSelfScope };
