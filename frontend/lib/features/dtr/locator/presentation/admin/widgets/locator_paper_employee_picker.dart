import 'package:flutter/material.dart';

/// One signed paper locator belongs to one employee, just like paper Leave.
class LocatorPaperEmployeePicker extends StatelessWidget {
  const LocatorPaperEmployeePicker({
    super.key,
    required this.search,
    required this.scrollController,
    required this.employees,
    required this.total,
    required this.loading,
    required this.error,
    required this.onSearchChanged,
    required this.onSearch,
    required this.onLoadMore,
    required this.onSelect,
  });

  final TextEditingController search;
  final ScrollController scrollController;
  final List<Map<String, dynamic>> employees;
  final int total;
  final bool loading;
  final String? error;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearch, onLoadMore;
  final ValueChanged<Map<String, dynamic>> onSelect;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Step 1 of 3 • Employee',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Select an employee',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Record one fully approved paper locator at a time. Select the employee named on the signed original.',
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('locator-filing-search'),
              controller: search,
              decoration: const InputDecoration(
                labelText: 'Search employees',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: onSearchChanged,
              onSubmitted: (_) => onSearch(),
            ),
          ],
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Expanded(child: Text(error!)),
              TextButton(
                onPressed: loading ? null : onSearch,
                child: const Text('Retry employees'),
              ),
            ],
          ),
        ),
      if (loading) const LinearProgressIndicator(),
      Expanded(
        child: ListView.builder(
          controller: scrollController,
          itemCount: employees.length + 1,
          itemBuilder: (context, index) {
            if (index == employees.length) {
              if (employees.isEmpty && !loading && error == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No employees found.'),
                );
              }
              return employees.length < total
                  ? TextButton(
                      onPressed: loading ? null : onLoadMore,
                      child: const Text('Load more employees'),
                    )
                  : const SizedBox.shrink();
            }
            final employee = employees[index];
            final department = employee['department_name']?.toString() ?? '';
            final employment =
                employee['employment_type']?.toString().replaceAll('_', ' ') ??
                '';
            return ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(employee['full_name']?.toString() ?? 'Employee'),
              subtitle: Text(department.isNotEmpty ? department : employment),
              trailing: const Icon(Icons.chevron_right),
              onTap: loading ? null : () => onSelect(employee),
            );
          },
        ),
      ),
    ],
  );
}
