import '../features/subscriptions/domain/membership_status.dart';

class DirectoryFilter {
  const DirectoryFilter(this.value, this.label, this.description);
  final String value, label, description;
}

List<DirectoryFilter> directoryFilters(String kind) => [
      const DirectoryFilter(
        'all',
        'All records',
        'Show every record on this screen',
      ),
      ...switch (kind) {
        'invoices' => const [
            DirectoryFilter('paid', 'Paid', 'Fully paid invoices'),
            DirectoryFilter(
              'pending',
              'Pending payment',
              'Unpaid, partially paid, or overdue invoices',
            ),
            DirectoryFilter(
                'unpaid', 'Unpaid', 'Invoices with no payment received'),
            DirectoryFilter(
              'partially_paid',
              'Partially paid',
              'Invoices with a remaining balance',
            ),
            DirectoryFilter('overdue', 'Overdue', 'Invoices marked overdue'),
            DirectoryFilter('voided', 'Voided', 'Cancelled invoices'),
          ],
        'subscriptions' => const [
            DirectoryFilter(
              'active',
              'Active',
              'Current memberships, including those expiring soon',
            ),
            DirectoryFilter(
              'expiring_soon',
              'Expiring within 7 days',
              'Memberships ending today or within the next 7 days',
            ),
            DirectoryFilter(
                'expired', 'Expired', 'Memberships that have ended'),
            DirectoryFilter(
                'paused', 'Paused', 'Memberships currently on hold'),
            DirectoryFilter(
              'scheduled_renewal',
              'Scheduled renewal',
              'Renewals waiting to start',
            ),
            DirectoryFilter(
              'pending_activation',
              'Pending activation',
              'Memberships waiting for activation',
            ),
            DirectoryFilter('draft', 'Draft', 'Memberships not yet activated'),
            DirectoryFilter('cancelled', 'Cancelled', 'Cancelled memberships'),
            DirectoryFilter('deleted', 'Deleted memberships',
                'Accidental entries removed from normal views; administrators can restore them'),
          ],
        'receipts' => const [
            DirectoryFilter('issued', 'Issued', 'Receipts issued for payments'),
            DirectoryFilter(
                'voided', 'Voided', 'Receipts that have been cancelled'),
          ],
        'members' || 'membership_packages' || 'employees' => [
            DirectoryFilter(
                'active',
                'Active',
                switch (kind) {
                  'members' => 'Member records marked active',
                  'employees' => 'Employees with active access',
                  _ => 'Packages available for membership creation',
                }),
            const DirectoryFilter(
                'inactive', 'Inactive', 'Records marked inactive'),
            const DirectoryFilter(
                'archived', 'Archived', 'Records kept for history'),
          ],
        _ => const <DirectoryFilter>[],
      },
      if (kind == 'members' || kind == 'membership_packages')
        const DirectoryFilter(
          'pending_sync',
          'Pending sync',
          'Local changes waiting to sync or needing attention',
        ),
    ];

bool matchesDirectoryFilter(
  String kind,
  Map data,
  String syncState,
  String filter,
) {
  if (kind == 'subscriptions') {
    if (data['deleted_at'] != null) return filter == 'deleted';
    if (filter == 'deleted') return false;
  }
  if (kind == 'invoices' && data['deleted_with_membership'] != null) {
    return false;
  }
  if (filter == 'all') return true;
  if (filter == 'pending_sync') return syncState != 'synced';
  if (kind == 'subscriptions') {
    return MembershipStatus(data).matchesFilter(filter);
  }
  if (kind == 'invoices' && filter == 'pending') {
    return const [
      'unpaid',
      'partially_paid',
      'overdue',
    ].contains(data['status']);
  }
  return data['status'] == filter;
}
