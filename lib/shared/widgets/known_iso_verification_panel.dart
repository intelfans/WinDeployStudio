import 'package:flutter/material.dart';

import '../../core/localization/strings.dart';
import '../../core/services/iso_parse_service.dart';
import '../../core/services/known_iso_verification_service.dart';

/// Shows image identity details only after the local file matched a bundled
/// checksum. A missing verification intentionally produces no visual state.
class KnownIsoVerificationPanel extends StatelessWidget {
  final KnownIsoVerification? verification;
  final IsoMetadata? iso;

  const KnownIsoVerificationPanel({
    super.key,
    required this.verification,
    this.iso,
  });

  @override
  Widget build(BuildContext context) {
    final result = verification;
    if (result == null) return const SizedBox.shrink();

    final locale = Localizations.localeOf(context);
    final imageName = result.image.getName(locale);
    final system = _systemDescription(context, imageName);
    final language = _languageDescription(context, result);
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      container: true,
      liveRegion: true,
      label:
          '${tr(context, 'known_iso_verified')}: $imageName. '
          '${tr(context, 'known_iso_system')}: $system. '
          '${tr(context, 'known_iso_language')}: $language.',
      child: DecoratedBox(
        key: const Key('known-iso-verification-panel'),
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.5),
          border: Border.all(color: colors.primary.withValues(alpha: 0.38)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_rounded,
                color: colors.primary,
                semanticLabel: '',
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tr(context, 'known_iso_verified')}: $imageName',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${tr(context, 'known_iso_system')}: $system',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${tr(context, 'known_iso_language')}: $language',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _systemDescription(BuildContext context, String imageName) {
    final values = <String>[
      iso?.windowsVersion?.trim() ?? '',
      iso?.edition?.trim() ?? '',
      if ((iso?.buildNumber ?? '').trim().isNotEmpty)
        '${tr(context, 'creator_build_prefix')} ${iso!.buildNumber!.trim()}',
      iso?.architecture?.trim() ?? '',
    ].where((value) => value.isNotEmpty).toList(growable: false);
    return values.isEmpty ? imageName : values.join(' • ');
  }

  String _languageDescription(
    BuildContext context,
    KnownIsoVerification result,
  ) {
    final detected = iso?.language?.trim();
    final detectedKey = _languageKeyForTag(detected);
    if (detectedKey != null) return tr(context, detectedKey);
    if (detected != null && detected.isNotEmpty) return detected;

    return tr(context, _knownImageLanguageKey(result.image.id));
  }
}

String? _languageKeyForTag(String? languageTag) {
  final normalized = languageTag?.trim().toLowerCase().replaceAll('_', '-');
  if (normalized == null || normalized.isEmpty) return null;
  if (normalized.startsWith('en')) return 'known_iso_language_english';
  if (normalized == 'zh' || normalized.startsWith('zh-cn')) {
    return 'known_iso_language_simplified_chinese';
  }
  if (normalized.startsWith('zh-')) {
    return 'known_iso_language_traditional_chinese';
  }
  return null;
}

String _knownImageLanguageKey(String imageId) {
  return switch (imageId) {
    'starvalleyx' => 'known_iso_language_simplified_chinese',
    'tiny10' ||
    'tiny11' ||
    'xlite10' ||
    'xlite11' ||
    'ltsc-win10-enterprise' ||
    'ltsc-win11-enterprise' ||
    'ltsc-win10-iot' ||
    'ltsc-win11-iot' => 'known_iso_language_english',
    _ => 'known_iso_language_not_specified',
  };
}
