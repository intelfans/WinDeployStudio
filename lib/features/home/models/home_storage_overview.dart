import '../../../core/services/disk_safety_service.dart';

/// A display-oriented snapshot of one connected external storage device.
///
/// This deliberately contains no write capability or mutable disk identity.
/// Home can use it to describe a device while all destructive flows continue
/// to work with their own [DiskInfo] safety checks.
class HomeStorageDeviceOverview {
  final int diskNumber;
  final String name;
  final int capacityBytes;
  final String capacityLabel;
  final String busType;
  final List<String> driveLetters;
  final bool isAvailable;

  const HomeStorageDeviceOverview({
    required this.diskNumber,
    required this.name,
    required this.capacityBytes,
    required this.capacityLabel,
    required this.busType,
    required this.driveLetters,
    required this.isAvailable,
  });

  factory HomeStorageDeviceOverview.fromDisk(DiskInfo disk) {
    return HomeStorageDeviceOverview(
      diskNumber: disk.diskNumber,
      name: _displayNameFor(disk),
      capacityBytes: disk.sizeBytes,
      capacityLabel: disk.sizeFormatted,
      busType: disk.busType,
      driveLetters: List.unmodifiable(disk.driveLetters),
      isAvailable: !disk.isOffline,
    );
  }

  static String _displayNameFor(DiskInfo disk) {
    final friendlyName = disk.friendlyName.trim();
    if (_isUsableName(friendlyName)) return friendlyName;

    final model = disk.model.trim();
    return _isUsableName(model) ? model : '';
  }

  static bool _isUsableName(String value) {
    if (value.isEmpty) return false;
    final normalized = value.toUpperCase();
    return normalized != 'N/A' &&
        normalized != 'UNKNOWN' &&
        normalized != 'UNKNOWN DISK';
  }
}

/// Summary data for the optional storage-device section on Home.
///
/// [devices] contains every safe, online external disk exposed by Windows.
/// The list is sorted by disk number so the Home display does not change order
/// merely because PowerShell changes its enumeration order.
class HomeStorageOverview {
  final List<HomeStorageDeviceOverview> devices;

  const HomeStorageOverview({required this.devices});

  const HomeStorageOverview.empty() : devices = const [];

  int get externalDeviceCount => devices.length;

  /// Retained as a convenience for callers that only need the first device.
  HomeStorageDeviceOverview? get primaryDevice =>
      devices.isEmpty ? null : devices.first;

  bool get isAvailable => devices.any((device) => device.isAvailable);

  bool get hasExternalDevice => devices.isNotEmpty;

  factory HomeStorageOverview.fromDisks(Iterable<DiskInfo> disks) {
    final availableDisks =
        disks.where((disk) => !disk.isOffline).toList(growable: false)
          ..sort((left, right) => left.diskNumber.compareTo(right.diskNumber));

    if (availableDisks.isEmpty) return const HomeStorageOverview.empty();

    return HomeStorageOverview(
      devices: List<HomeStorageDeviceOverview>.unmodifiable(
        availableDisks.map(HomeStorageDeviceOverview.fromDisk),
      ),
    );
  }
}
