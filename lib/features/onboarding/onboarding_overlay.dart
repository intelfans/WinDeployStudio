import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/localization/strings.dart';
import '../../shared/widgets/app_navigation_shell.dart';

enum OnboardingSection {
  home,
  images,
  creator,
  toGo,
  benchmark,
  diskTools,
  logs,
  ai,
  tools,
  settings,
}

class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({
    super.key,
    this.section,
    this.markCompletedOnExit = false,
    this.onClosed,
    this.router,
  });

  static const completedPreferenceKey = 'onboarding_v1_completed';
  static const completedVersionPreferenceKey =
      'onboarding_last_completed_version';

  final OnboardingSection? section;
  final bool markCompletedOnExit;
  final VoidCallback? onClosed;
  final GoRouter? router;

  static OverlayEntry? _activeEntry;
  static Completer<void>? _activeCompleter;

  static Future<void> show(
    BuildContext context, {
    OnboardingSection? section,
    bool markCompletedOnExit = false,
  }) {
    final active = _activeCompleter;
    if (active != null) return active.future;

    final overlay = Overlay.of(context, rootOverlay: true);
    final router = GoRouter.maybeOf(context);
    final completer = Completer<void>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => OnboardingOverlay(
        section: section,
        markCompletedOnExit: markCompletedOnExit,
        router: router,
        onClosed: () {
          entry.remove();
          if (identical(_activeEntry, entry)) {
            _activeEntry = null;
            _activeCompleter = null;
          }
          if (!completer.isCompleted) completer.complete();
        },
      ),
    );
    _activeEntry = entry;
    _activeCompleter = completer;
    overlay.insert(entry);
    return completer.future;
  }

  static Future<bool> hasCompleted() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(completedVersionPreferenceKey) ==
        AppConstants.appVersion;
  }

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay>
    with TickerProviderStateMixin {
  late List<_GuideStep> _steps;
  late final AnimationController _pulseController;
  Timer? _continueTimer;
  GoRouter? _router;
  int _index = 0;
  bool _openedCurrentChild = false;
  bool _closing = false;
  bool _appeared = false;
  bool _exploring = false;
  bool _continueReady = false;
  bool _detailsExpanded = false;
  bool _switchPromptOpen = false;
  String? _lastObservedPath;
  OnboardingSection? _pendingSwitchSection;
  String? _pendingSwitchPath;
  Completer<_TourSwitchDecision>? _switchCompleter;

  bool get _isFullTour => widget.section == null;
  bool get _isSingleSectionTour => !_isFullTour;

  @override
  void initState() {
    super.initState();
    _steps = widget.section == null
        ? List.unmodifiable(_allGuideSteps)
        : List.unmodifiable(
            _allGuideSteps.where((step) => step.section == widget.section),
          );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _router = widget.router ?? GoRouter.maybeOf(context);
      if (_router != null) {
        _lastObservedPath =
            _router!.routerDelegate.currentConfiguration.uri.path;
        _router!.routerDelegate.addListener(_handleRouteChanged);
      }
      setState(() => _appeared = true);
    });
  }

  @override
  void dispose() {
    _continueTimer?.cancel();
    _router?.routerDelegate.removeListener(_handleRouteChanged);
    _pulseController.dispose();
    super.dispose();
  }

  _GuideStep get _step => _steps[_index];

  Future<void> _close({bool complete = false}) async {
    if (_closing) return;
    _closing = true;
    if (complete || widget.markCompletedOnExit) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(OnboardingOverlay.completedPreferenceKey, true);
      await preferences.setString(
        OnboardingOverlay.completedVersionPreferenceKey,
        AppConstants.appVersion,
      );
    }
    if (!mounted) return;
    _switchCompleter?.complete(_TourSwitchDecision.stay);
    setState(() => _appeared = false);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    final onClosed = widget.onClosed;
    if (onClosed != null) {
      onClosed();
    } else {
      await Navigator.of(context).maybePop();
    }
  }

  void _showStep(int index) {
    if (index >= _steps.length) {
      _close(complete: true);
      return;
    }
    _continueTimer?.cancel();
    setState(() {
      _index = index;
      _openedCurrentChild = false;
      _exploring = false;
      _continueReady = false;
      _detailsExpanded = false;
    });
  }

  void _next() {
    final nextIndex = _index + 1;
    if (nextIndex >= _steps.length) {
      _showStep(nextIndex);
      return;
    }

    // Child pages are rendered as nested routes. When the next step points
    // at another child (or another section), return to its stable parent
    // first so the real navigation/card anchor exists before highlighting it.
    if (_step.kind == _GuideStepKind.child) {
      final nextStep = _steps[nextIndex];
      final nextRoot = _rootPathFor(nextStep.path);
      final currentPath = _router?.routerDelegate.currentConfiguration.uri.path;
      _showStep(nextIndex);
      if (nextRoot != null && currentPath != nextRoot) {
        context.go(nextRoot);
      }
      return;
    }
    _showStep(nextIndex);
  }

  void _previous() {
    if (_index == 0) return;
    final previousStep = _steps[_index - 1];
    final previousPath = previousStep.path;
    _showStep(_index - 1);
    final currentPath = _router?.routerDelegate.currentConfiguration.uri.path;
    if (currentPath != previousPath) {
      context.go(previousPath);
    }
  }

  void _skipSection() {
    final section = _step.section;
    var next = _index + 1;
    while (next < _steps.length && _steps[next].section == section) {
      next++;
    }
    _showStep(next);
  }

  void _openNavigationStep() {
    context.go(_step.path);
    _next();
  }

  void _openChildStep() {
    context.go(_step.path);
    setState(() => _openedCurrentChild = true);
    _beginExploration();
  }

  void _beginExploration() {
    _continueTimer?.cancel();
    setState(() {
      _exploring = true;
      _continueReady = false;
      _detailsExpanded = false;
    });
    _continueTimer = Timer(const Duration(milliseconds: 2800), () {
      if (!mounted || !_exploring) return;
      setState(() => _continueReady = true);
    });
  }

  void _handleRouteChanged() {
    final router = _router;
    if (router == null || !mounted) return;
    final path = router.routerDelegate.currentConfiguration.uri.path;
    if (path == _lastObservedPath) return;
    _lastObservedPath = path;

    final directChildIndex = _steps.indexWhere(
      (step) => step.kind == _GuideStepKind.child && step.path == path,
    );
    if (_isFullTour &&
        directChildIndex >= 0 &&
        _steps[directChildIndex].section == _step.section &&
        directChildIndex != _index) {
      _showDirectChildIntro(directChildIndex);
      return;
    }

    final currentRoot = _rootPathFor(_step.path);
    if (_step.kind == _GuideStepKind.child &&
        _exploring &&
        currentRoot != null &&
        path == currentRoot) {
      _showParentPageIntro(_step.section);
      return;
    }

    final section = _sectionForPath(path);
    if (!_exploring ||
        section == null ||
        section == _step.section ||
        _switchPromptOpen) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _askToSwitchTour(section, path);
    });
  }

  void _showDirectChildIntro(int index) {
    _continueTimer?.cancel();
    setState(() {
      _index = index;
      _openedCurrentChild = true;
      _exploring = false;
      _continueReady = false;
      _detailsExpanded = false;
    });
  }

  void _showParentPageIntro(OnboardingSection section) {
    final parentIndex = _steps.indexWhere(
      (step) => step.section == section && step.kind == _GuideStepKind.page,
    );
    if (parentIndex < 0) return;
    _continueTimer?.cancel();
    setState(() {
      _index = parentIndex;
      _openedCurrentChild = false;
      _exploring = false;
      _continueReady = false;
      _detailsExpanded = false;
    });
  }

  Future<void> _askToSwitchTour(
    OnboardingSection targetSection,
    String targetPath,
  ) async {
    if (_switchPromptOpen || !mounted) return;
    _switchCompleter?.complete(_TourSwitchDecision.stay);
    final completer = Completer<_TourSwitchDecision>();
    setState(() {
      _switchPromptOpen = true;
      _pendingSwitchSection = targetSection;
      _pendingSwitchPath = targetPath;
      _switchCompleter = completer;
    });
    final decision = await completer.future;
    _switchPromptOpen = false;
    _pendingSwitchSection = null;
    _pendingSwitchPath = null;
    _switchCompleter = null;
    if (!mounted) return;
    if (decision == _TourSwitchDecision.end) {
      await _close(complete: true);
    } else if (decision == _TourSwitchDecision.switchTour) {
      _switchToSection(targetSection, targetPath);
    } else {
      context.go(_step.path);
    }
  }

  void _resolveSwitch(_TourSwitchDecision decision) {
    final completer = _switchCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(decision);
  }

  void _switchToSection(OnboardingSection section, String currentPath) {
    final nextSteps = _isFullTour
        ? List<_GuideStep>.of(_allGuideSteps)
        : _allGuideSteps.where((step) => step.section == section).toList();
    var nextIndex = nextSteps.indexWhere(
      (step) =>
          step.section == section &&
          step.kind == _GuideStepKind.child &&
          step.path == currentPath,
    );
    if (nextIndex < 0) {
      nextIndex = nextSteps.indexWhere(
        (step) => step.section == section && step.kind == _GuideStepKind.page,
      );
    }
    if (nextIndex < 0) return;
    _continueTimer?.cancel();
    setState(() {
      _steps = nextSteps;
      _index = nextIndex;
      _openedCurrentChild = _step.kind == _GuideStepKind.child;
      _exploring = false;
      _continueReady = false;
      _detailsExpanded = false;
    });
  }

  Rect? _navigationTargetRect() {
    final targetKey = _step.targetKey;
    if (targetKey != null) {
      final targetContext = targetKey.currentContext;
      final renderObject = targetContext?.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        final origin = renderObject.localToGlobal(Offset.zero);
        return (origin & renderObject.size).inflate(6);
      }
    }
    final navIndex = _step.navIndex;
    if (navIndex == null ||
        navIndex >= AppNavigationKeys.destinationKeys.length) {
      return null;
    }
    final targetContext =
        AppNavigationKeys.destinationKeys[navIndex].currentContext;
    final renderObject = targetContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final origin = renderObject.localToGlobal(Offset.zero);
    return (origin & renderObject.size).inflate(6);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final targetRect =
        _exploring ||
            (_step.kind == _GuideStepKind.child && _openedCurrentChild)
        ? null
        : _step.kind == _GuideStepKind.page
        ? null
        : _navigationTargetRect();

    return AnimatedOpacity(
      opacity: _appeared ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final compact = size.width < 760;
            final interactive = _exploring && !_switchPromptOpen;
            return Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: interactive,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (!interactive)
                          ClipPath(
                            clipper: _SpotlightClipper(targetRect),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                sigmaX: 2.2,
                                sigmaY: 2.2,
                              ),
                              child: const ColoredBox(
                                color: Colors.transparent,
                              ),
                            ),
                          ),
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) => CustomPaint(
                            painter: _SpotlightPainter(
                              target: targetRect,
                              pulse: _pulseController.value,
                              overlayColor: Colors.black.withValues(
                                alpha: interactive ? 0.0 : 0.58,
                              ),
                              accent: colors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!interactive)
                  const Positioned.fill(
                    child: ModalBarrier(
                      dismissible: false,
                      color: Colors.transparent,
                    ),
                  ),
                if (targetRect != null)
                  Positioned.fromRect(
                    key: const Key('onboarding-spotlight-target'),
                    rect: targetRect,
                    child: Semantics(
                      button: true,
                      label:
                          '${_copy(context, 'open')} ${tr(context, _step.titleKey)}',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _step.kind == _GuideStepKind.child
                            ? _openChildStep
                            : _openNavigationStep,
                      ),
                    ),
                  ),
                if (_switchPromptOpen)
                  _buildSwitchPrompt(context, size: size, compact: compact)
                else if (_exploring && !_detailsExpanded)
                  _buildExploreDock(context, size: size, compact: compact)
                else
                  _buildGuideCard(
                    context,
                    size: size,
                    compact: compact,
                    targetRect: targetRect,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSwitchPrompt(
    BuildContext context, {
    required Size size,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final targetSection = _pendingSwitchSection;
    final targetPath = _pendingSwitchPath;
    if (targetSection == null || targetPath == null) {
      return const SizedBox.shrink();
    }
    final targetLabel = onboardingSectionLabel(context, targetSection);
    final currentLabel = onboardingSectionLabel(context, _step.section);
    final width = compact ? size.width - 32 : 500.0;
    return Positioned(
      left: (size.width - width) / 2,
      top: (size.height - 270).clamp(80.0, size.height - 220),
      width: width,
      child: AnimatedScale(
        scale: _switchPromptOpen ? 1 : 0.96,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 38,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.14),
                blurRadius: 28,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.route_rounded,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _copy(
                        context,
                        _isSingleSectionTour
                            ? 'endTourQuestion'
                            : 'switchTitle',
                      ),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _isSingleSectionTour
                    ? _copy(context, 'endTourSwitchMessage')
                    : _switchMessage(context, targetLabel, currentLabel),
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.55,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _resolveSwitch(_TourSwitchDecision.stay),
                    child: Text(
                      _copy(
                        context,
                        _isSingleSectionTour ? 'continueTour' : 'stayTour',
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _resolveSwitch(
                      _isSingleSectionTour
                          ? _TourSwitchDecision.end
                          : _TourSwitchDecision.switchTour,
                    ),
                    style: _isSingleSectionTour
                        ? FilledButton.styleFrom(
                            backgroundColor: colors.error,
                            foregroundColor: colors.onError,
                          )
                        : null,
                    icon: Icon(
                      _isSingleSectionTour
                          ? Icons.close_rounded
                          : Icons.swap_horiz_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _copy(
                        context,
                        _isSingleSectionTour ? 'endTour' : 'switchTour',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuideCard(
    BuildContext context, {
    required Size size,
    required bool compact,
    required Rect? targetRect,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = AppVisualTokens.of(context);
    final maxWidth = compact ? size.width - 32 : 440.0;
    final left = compact
        ? 16.0
        : targetRect != null
        ? _guideCardLeft(size, targetRect, maxWidth)
        : size.width - maxWidth - 32;
    final top = compact
        ? size.height - 360.0
        : targetRect != null
        ? (targetRect.center.dy - 110).clamp(80.0, size.height - 300)
        : 110.0;

    final topPosition = top.clamp(76.0, size.height - 220);
    return AnimatedPositioned(
      key: ValueKey('onboarding-position-${_step.id}'),
      duration: tokens.motionDuration,
      curve: Curves.easeOutCubic,
      left: left,
      top: topPosition,
      width: maxWidth,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 340),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(animation),
            alignment: Alignment.topLeft,
            child: child,
          ),
        ),
        child: ConstrainedBox(
          key: ValueKey('onboarding-card-${_step.id}'),
          constraints: BoxConstraints(
            maxHeight: size.height - topPosition - 24,
          ),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.24),
                  blurRadius: 36,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.12),
                  blurRadius: 28,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_step.icon, color: colors.onPrimaryContainer),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _copy(context, 'title'),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            tr(context, _step.titleKey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${_index + 1}/${_steps.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: _buildStepDetails(context),
                  ),
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_index + 1) / _steps.length,
                    minHeight: 5,
                    backgroundColor: colors.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_index > 0 &&
                        _step.section != OnboardingSection.settings)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: IconButton(
                          tooltip: _copy(context, 'back'),
                          onPressed: _previous,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                    Expanded(
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          TextButton.icon(
                            key: const Key('onboarding-close-all'),
                            onPressed: () => _close(complete: true),
                            style: TextButton.styleFrom(
                              foregroundColor: colors.error,
                            ),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: Text(_copy(context, 'endTour')),
                          ),
                          if (!_isSingleSectionTour &&
                              _step.section != OnboardingSection.settings)
                            TextButton(
                              key: const Key('onboarding-skip-section'),
                              onPressed: _skipSection,
                              child: Text(_copy(context, 'skipSection')),
                            ),
                          if (_step.kind == _GuideStepKind.navigation)
                            FilledButton.icon(
                              onPressed: _openNavigationStep,
                              icon: const Icon(
                                Icons.touch_app_rounded,
                                size: 18,
                              ),
                              label: Text(_copy(context, 'open')),
                            )
                          else if ((_step.kind == _GuideStepKind.page &&
                                  !_exploring) ||
                              (_step.kind == _GuideStepKind.child &&
                                  (!_openedCurrentChild || !_exploring)))
                            FilledButton.icon(
                              key: Key(
                                _step.kind == _GuideStepKind.child &&
                                        !_openedCurrentChild
                                    ? 'onboarding-open-child'
                                    : 'onboarding-start-exploring',
                              ),
                              onPressed:
                                  _step.kind == _GuideStepKind.child &&
                                      !_openedCurrentChild
                                  ? _openChildStep
                                  : _beginExploration,
                              icon: const Icon(Icons.explore_rounded, size: 18),
                              label: Text(
                                _step.kind == _GuideStepKind.child &&
                                        !_openedCurrentChild
                                    ? _copy(context, 'openAndExplore')
                                    : _copy(context, 'startExploring'),
                              ),
                            )
                          else
                            FilledButton.icon(
                              key: const Key('onboarding-card-next'),
                              onPressed: _next,
                              icon: Icon(
                                _index == _steps.length - 1
                                    ? Icons.check_rounded
                                    : Icons.arrow_forward_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _index == _steps.length - 1
                                    ? _copy(context, 'done')
                                    : _copy(context, 'next'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _guideCardLeft(Size size, Rect targetRect, double maxWidth) {
    final rightCandidate = targetRect.right + 20;
    if (rightCandidate + maxWidth <= size.width - 20) {
      return rightCandidate;
    }
    final leftCandidate = targetRect.left - maxWidth - 20;
    if (leftCandidate >= 20) return leftCandidate;
    return (size.width - maxWidth - 32).clamp(20.0, size.width - maxWidth - 20);
  }

  Widget _buildStepDetails(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final content = _guideContent(context, _step);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          content.summary,
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.55,
            color: colors.onSurfaceVariant,
          ),
        ),
        if (content.tryItems.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            _copy(context, 'tryLabel'),
            style: theme.textTheme.labelLarge?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in content.tryItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Icon(Icons.circle, size: 6, color: colors.primary),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.45,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildExploreDock(
    BuildContext context, {
    required Size size,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final width = compact
        ? size.width - 32
        : (_isSingleSectionTour || _index == _steps.length - 1)
        ? 390.0
        : 470.0;
    return PositionedDirectional(
      end: compact ? 16 : 28,
      bottom: compact ? 16 : 28,
      width: width,
      child: AnimatedScale(
        scale: _appeared ? 1 : 0.94,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.1),
                blurRadius: 24,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_step.icon, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  key: const Key('onboarding-explore-details'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _detailsExpanded = true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(context, _step.titleKey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _copy(context, 'exploringHint'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_isSingleSectionTour || _index == _steps.length - 1)
                FilledButton.icon(
                  key: const Key('onboarding-close-all'),
                  onPressed: () => _close(complete: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(_copy(context, 'endTour')),
                )
              else ...[
                FilledButton.icon(
                  key: const Key('onboarding-close-all'),
                  onPressed: () => _close(complete: true),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(_copy(context, 'endTour')),
                ),
                const SizedBox(width: 14),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: _continueReady
                      ? FilledButton.icon(
                          key: const ValueKey('onboarding-explore-next'),
                          onPressed: _next,
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 17,
                          ),
                          label: Text(_copy(context, 'next')),
                        )
                      : SizedBox(
                          key: const ValueKey('onboarding-explore-waiting'),
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.3,
                            color: colors.primary,
                          ),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _TourSwitchDecision { stay, switchTour, end }

String? _rootPathFor(String path) {
  if (path == '/' || path.isEmpty) return '/';
  if (path.startsWith('/mirror')) return '/mirror';
  if (path.startsWith('/creator')) return '/creator';
  if (path.startsWith('/wtg')) return '/wtg';
  if (path.startsWith('/benchmark')) return '/benchmark';
  if (path.startsWith('/disk-tools')) return '/disk-tools';
  if (path.startsWith('/logs')) return '/logs';
  if (path.startsWith('/ai')) return '/ai';
  if (path.startsWith('/tools')) return '/tools';
  if (path.startsWith('/settings')) return '/settings';
  return null;
}

OnboardingSection? _sectionForPath(String path) {
  if (path == '/' || path.isEmpty) return OnboardingSection.home;
  if (path.startsWith('/mirror')) return OnboardingSection.images;
  if (path.startsWith('/creator')) return OnboardingSection.creator;
  if (path.startsWith('/wtg')) return OnboardingSection.toGo;
  if (path.startsWith('/benchmark')) return OnboardingSection.benchmark;
  if (path.startsWith('/disk-tools')) return OnboardingSection.diskTools;
  if (path.startsWith('/logs')) return OnboardingSection.logs;
  if (path.startsWith('/ai')) return OnboardingSection.ai;
  if (path.startsWith('/tools')) return OnboardingSection.tools;
  if (path.startsWith('/settings')) return OnboardingSection.settings;
  return null;
}

enum _GuideStepKind { navigation, page, child }

class _GuideStep {
  const _GuideStep({
    required this.id,
    required this.section,
    required this.path,
    required this.titleKey,
    required this.descriptionKey,
    required this.icon,
    required this.kind,
    this.navIndex,
    this.targetKey,
  });

  final String id;
  final OnboardingSection section;
  final String path;
  final String titleKey;
  final String descriptionKey;
  final IconData icon;
  final _GuideStepKind kind;
  final int? navIndex;
  final GlobalKey? targetKey;
}

final _allGuideSteps = <_GuideStep>[
  _GuideStep(
    id: 'home-nav',
    section: OnboardingSection.home,
    path: '/',
    titleKey: 'nav_home',
    descriptionKey: 'home_subtitle',
    icon: Icons.home_rounded,
    kind: _GuideStepKind.navigation,
    navIndex: 0,
  ),
  _GuideStep(
    id: 'home-page',
    section: OnboardingSection.home,
    path: '/',
    titleKey: 'nav_home',
    descriptionKey: 'home_subtitle',
    icon: Icons.dashboard_customize_rounded,
    kind: _GuideStepKind.page,
  ),
  _GuideStep(
    id: 'images-nav',
    section: OnboardingSection.images,
    path: '/mirror',
    titleKey: 'nav_images',
    descriptionKey: 'images_subtitle',
    icon: Icons.cloud_rounded,
    kind: _GuideStepKind.navigation,
    navIndex: 1,
  ),
  _GuideStep(
    id: 'images-page',
    section: OnboardingSection.images,
    path: '/mirror',
    titleKey: 'images_title',
    descriptionKey: 'images_subtitle',
    icon: Icons.image_search_rounded,
    kind: _GuideStepKind.page,
  ),
  _GuideStep(
    id: 'creator-nav',
    section: OnboardingSection.creator,
    path: '/creator',
    titleKey: 'nav_creator',
    descriptionKey: 'home_bootable_usb_desc',
    icon: Icons.usb_rounded,
    kind: _GuideStepKind.navigation,
    navIndex: 2,
  ),
  _GuideStep(
    id: 'creator-page',
    section: OnboardingSection.creator,
    path: '/creator',
    titleKey: 'home_bootable_usb',
    descriptionKey: 'home_bootable_usb_desc',
    icon: Icons.install_desktop_rounded,
    kind: _GuideStepKind.page,
  ),
  _GuideStep(
    id: 'togo-nav',
    section: OnboardingSection.toGo,
    path: '/wtg',
    titleKey: 'nav_wtg',
    descriptionKey: 'home_wtg_desc',
    icon: Icons.computer_rounded,
    kind: _GuideStepKind.navigation,
    navIndex: 3,
  ),
  _GuideStep(
    id: 'togo-page',
    section: OnboardingSection.toGo,
    path: '/wtg',
    titleKey: 'home_wtg',
    descriptionKey: 'home_wtg_desc',
    icon: Icons.laptop_windows_rounded,
    kind: _GuideStepKind.page,
  ),
  _GuideStep(
    id: 'benchmark-nav',
    section: OnboardingSection.benchmark,
    path: '/benchmark',
    titleKey: 'nav_benchmark',
    descriptionKey: 'bench_subtitle',
    icon: Icons.monitor_heart_rounded,
    kind: _GuideStepKind.navigation,
    navIndex: 4,
  ),
  _GuideStep(
    id: 'benchmark-page',
    section: OnboardingSection.benchmark,
    path: '/benchmark',
    titleKey: 'bench_title',
    descriptionKey: 'bench_subtitle',
    icon: Icons.speed_rounded,
    kind: _GuideStepKind.page,
  ),
  _GuideStep(
    id: 'benchmark-history',
    section: OnboardingSection.benchmark,
    path: '/benchmark/history',
    titleKey: 'benchmark_history_title',
    descriptionKey: 'benchmark_history_subtitle',
    icon: Icons.history_rounded,
    kind: _GuideStepKind.child,
    targetKey: AppNavigationKeys.benchmarkHistoryKey,
  ),
  _GuideStep(
    id: 'disktools-nav',
    section: OnboardingSection.diskTools,
    path: '/disk-tools',
    titleKey: 'disk_tools_title',
    descriptionKey: 'disk_tools_subtitle',
    icon: Icons.storage_rounded,
    kind: _GuideStepKind.navigation,
    navIndex: 5,
  ),
  _GuideStep(
    id: 'disktools-page',
    section: OnboardingSection.diskTools,
    path: '/disk-tools',
    titleKey: 'disk_tools_title',
    descriptionKey: 'disk_tools_subtitle',
    icon: Icons.build_circle_rounded,
    kind: _GuideStepKind.page,
  ),
  _GuideStep(
    id: 'disk-diagnostics',
    section: OnboardingSection.diskTools,
    path: '/disk-tools/diagnostics',
    titleKey: 'disk_tools_diagnostics_title',
    descriptionKey: 'disk_tools_diagnostics_desc',
    icon: Icons.health_and_safety_rounded,
    kind: _GuideStepKind.child,
    targetKey: AppNavigationKeys.diskDiagnosticsKey,
  ),
  _GuideStep(
    id: 'boot-repair',
    section: OnboardingSection.diskTools,
    path: '/disk-tools/boot-repair',
    titleKey: 'disk_tools_boot_repair_title',
    descriptionKey: 'disk_tools_boot_repair_desc',
    icon: Icons.settings_backup_restore_rounded,
    kind: _GuideStepKind.child,
    targetKey: AppNavigationKeys.bootRepairKey,
  ),
  _GuideStep(
    id: 'logs-nav',
    section: OnboardingSection.logs,
    path: '/logs',
    titleKey: 'nav_logs',
    descriptionKey: 'logs_subtitle',
    icon: Icons.receipt_long_rounded,
    kind: _GuideStepKind.navigation,
    navIndex: 6,
  ),
  _GuideStep(
    id: 'logs-page',
    section: OnboardingSection.logs,
    path: '/logs',
    titleKey: 'logs_title',
    descriptionKey: 'logs_subtitle',
    icon: Icons.manage_search_rounded,
    kind: _GuideStepKind.page,
  ),
  _GuideStep(
    id: 'ai-nav',
    section: OnboardingSection.ai,
    path: '/ai',
    titleKey: 'nav_ai',
    descriptionKey: 'ai_welcome_desc',
    icon: Icons.auto_awesome_rounded,
    kind: _GuideStepKind.navigation,
    navIndex: 7,
  ),
  _GuideStep(
    id: 'ai-page',
    section: OnboardingSection.ai,
    path: '/ai',
    titleKey: 'nav_ai',
    descriptionKey: 'ai_welcome_desc',
    icon: Icons.smart_toy_rounded,
    kind: _GuideStepKind.page,
  ),
  _GuideStep(
    id: 'tools-nav',
    section: OnboardingSection.tools,
    path: '/tools',
    titleKey: 'nav_tools',
    descriptionKey: 'tools_subtitle',
    icon: Icons.handyman_rounded,
    kind: _GuideStepKind.navigation,
    navIndex: 8,
  ),
  _GuideStep(
    id: 'tools-page',
    section: OnboardingSection.tools,
    path: '/tools',
    titleKey: 'tools_title',
    descriptionKey: 'tools_subtitle',
    icon: Icons.extension_rounded,
    kind: _GuideStepKind.page,
  ),
  _GuideStep(
    id: 'settings-nav',
    section: OnboardingSection.settings,
    path: '/settings',
    titleKey: 'nav_settings',
    descriptionKey: 'settings_subtitle',
    icon: Icons.settings_rounded,
    kind: _GuideStepKind.navigation,
    navIndex: 9,
  ),
  _GuideStep(
    id: 'settings-page',
    section: OnboardingSection.settings,
    path: '/settings',
    titleKey: 'settings_title',
    descriptionKey: '__settings__',
    icon: Icons.tune_rounded,
    kind: _GuideStepKind.page,
  ),
];

String onboardingSectionLabel(BuildContext context, OnboardingSection section) {
  final key = switch (section) {
    OnboardingSection.home => 'nav_home',
    OnboardingSection.images => 'nav_images',
    OnboardingSection.creator => 'nav_creator',
    OnboardingSection.toGo => 'nav_wtg',
    OnboardingSection.benchmark => 'nav_benchmark',
    OnboardingSection.diskTools => 'disk_tools_title',
    OnboardingSection.logs => 'nav_logs',
    OnboardingSection.ai => 'nav_ai',
    OnboardingSection.tools => 'nav_tools',
    OnboardingSection.settings => 'nav_settings',
  };
  return tr(context, key);
}

class _GuideContent {
  const _GuideContent(this.summary, [this.tryItems = const []]);

  final String summary;
  final List<String> tryItems;
}

_GuideContent _guideContent(BuildContext context, _GuideStep step) {
  if (step.kind == _GuideStepKind.navigation) {
    return _GuideContent(_copy(context, 'navigationHint'));
  }
  final code = normalizeLocaleCode(
    localeCodeFromLocale(Localizations.localeOf(context)),
  );
  final map = switch (code) {
    'zh' => _guideZh,
    'zh_TW' => _guideZhTw,
    'en' => _guideEn,
    _ => null,
  };
  if (map != null && map[step.id] != null) return map[step.id]!;
  return _GuideContent(
    step.descriptionKey == '__settings__'
        ? _copy(context, 'settingsDescription')
        : tr(context, step.descriptionKey),
    [_copy(context, 'genericExplore1'), _copy(context, 'genericExplore2')],
  );
}

String _switchMessage(
  BuildContext context,
  String targetLabel,
  String currentLabel,
) {
  final code = normalizeLocaleCode(
    localeCodeFromLocale(Localizations.localeOf(context)),
  );
  if (code == 'zh') {
    return '你正在查看“$targetLabel”。要切换到它的导览吗？选择“继续当前导览”会返回“$currentLabel”并保留当前进度。';
  }
  if (code == 'zh_TW') {
    return '你正在查看「$targetLabel」。要切換到它的導覽嗎？選擇「繼續目前導覽」會返回「$currentLabel」並保留目前進度。';
  }
  return 'You opened $targetLabel. Switch the tour to this section? Choosing “Stay with current tour” returns to $currentLabel and keeps your progress.';
}

const _guideEn = <String, _GuideContent>{
  'home-page': _GuideContent(
    'Your workspace brings the most useful actions together: quick start cards, recent images, and a live view of connected storage. It is designed to be a calm launch point rather than a dashboard you must configure before using the app.',
    [
      'Open a recent image or a quick-start card to see how the app keeps common tasks one click away.',
      'Scroll through the storage overview and notice that cards update independently of the rest of the page.',
    ],
  ),
  'images-page': _GuideContent(
    'Image Library is the safe place to learn about an image before writing anything. Each detail view explains the edition, language, size, available channels, and known checksums when they are available.',
    [
      'Choose a category, open an image detail page, and read its compatibility notes.',
      'Try the download choices without starting a USB operation; the tour never writes to a drive.',
    ],
  ),
  'creator-page': _GuideContent(
    'Installation Media walks through creating a bootable installer. The source area validates the selected ISO, the target area protects you from selecting the wrong disk, and the final review shows exactly what will be changed.',
    [
      'Select an ISO area and inspect the validation message before choosing a device.',
      'Review the partition and filesystem options, then leave the final write action untouched during this tour.',
    ],
  ),
  'togo-page': _GuideContent(
    'To Go creates a portable Windows workspace. It validates Windows image metadata, firmware layout, supported options, drivers, and the target disk before writing. Linux portable workspaces are planned for a future release; use Linux Installation Media when you need a bootable Linux installer now.',
    [
      'Select a Windows ISO and review the detected edition and compatibility guidance.',
      'Open advanced options and read the firmware, filesystem, and driver notes without starting a deployment.',
    ],
  ),
  'benchmark-page': _GuideContent(
    'Disk Test measures storage behavior with readable progress states for sequential and random workloads. Results are saved with the drive identity so you can compare devices later instead of relying on a single number.',
    [
      'Choose a test profile and inspect the workload selector and live chart.',
      'Open history to see how comparison, export, filtering, and deletion work together.',
    ],
  ),
  'benchmark-history': _GuideContent(
    'Test History is a workspace for your saved measurements. Select multiple records to compare different drives, export a clearly named report, or remove only the records you choose.',
    [
      'Select two records from different devices and open the comparison view.',
      'Try the export menu and inspect the identity, test data, and chart included in the report.',
    ],
  ),
  'disktools-page': _GuideContent(
    'Disk Tools groups maintenance tasks that need extra care. The overview explains what each tool changes and routes you to diagnostics or boot repair without hiding the safety boundary.',
    [
      'Open a tool card to read its prerequisites and the kind of confirmation it requires.',
      'Use the back navigation to return here; the tour follows secondary pages as part of this section.',
    ],
  ),
  'disk-diagnostics': _GuideContent(
    'Disk Diagnostics presents health, temperature, firmware, and identity information gathered through the Windows storage stack and the project helper. Bridged USB devices are shown when the bridge exposes the required data; unavailable fields remain clearly marked.',
    [
      'Browse the health summary and the per-device details without running a repair action.',
      'Try refreshing the device list after connecting or disconnecting a drive.',
    ],
  ),
  'boot-repair': _GuideContent(
    'BCD / EFI Boot Repair focuses on inspecting and repairing boot entries. The workflow creates a rollback point before changes and keeps scan, preview, and apply as separate steps.',
    [
      'Run through the scan and preview screens to see what would be changed.',
      'Stop before applying a repair; the onboarding never modifies boot data.',
    ],
  ),
  'logs-page': _GuideContent(
    'Log Center turns long-running work into an auditable timeline. Filters, severity markers, details, and export tools help you explain a failure without copying an entire log folder.',
    [
      'Filter by level and open one entry to view its structured details.',
      'Use the menu on the right to copy or export a focused slice of the log.',
    ],
  ),
  'ai-page': _GuideContent(
    'AI Assistant can explain test records, image compatibility, and deployment decisions using the context you choose to share. Endpoint, model, and key settings stay under your control, and the assistant reports when it cannot reach a service.',
    [
      'Open the service settings to review the endpoint and model without sending a request.',
      'Ask a short question or attach selected disk-test records, then inspect the generated explanation.',
    ],
  ),
  'tools-page': _GuideContent(
    'Tools contains focused utilities that support the main workflows without adding another layer of navigation. Each tool opens in its own surface and keeps destructive actions behind explicit confirmation.',
    [
      'Open a utility and inspect its input and output areas.',
      'Return to the tools grid and notice that the main navigation remains available.',
    ],
  ),
  'settings-page': _GuideContent(
    'Settings is where the app becomes yours: appearance, language, update sources, AI services, permissions, and this tour are all grouped into predictable sections. Changes apply immediately and are kept locally.',
    [
      'Switch the visual style or language and watch the interface adapt without restarting.',
      'Use App tour to replay the complete tour or jump directly to one section later.',
    ],
  ),
};

const _guideZh = <String, _GuideContent>{
  'home-page': _GuideContent(
    '首页把最常用的操作集中在一起：快速开始、最近镜像和存储设备概览。它是可以直接使用的工作区，不需要先完成复杂配置。',
    ['打开最近镜像或快速开始卡片，体验常用操作的一键入口。', '浏览存储设备概览，观察各卡片独立加载和更新。'],
  ),
  'images-page': _GuideContent(
    '镜像中心用于在写入之前了解镜像。详情页会说明版本、语言、大小、下载渠道，以及已知时的校验值和兼容性提醒。',
    ['选择一个分类，打开镜像详情并阅读适用性说明。', '可以体验下载选项，但导览不会写入任何磁盘。'],
  ),
  'creator-page': _GuideContent(
    '安装盘制作会分阶段引导你创建启动盘。镜像区域负责校验 ISO，目标区域保护你避免选错磁盘，最后的确认页会列出即将发生的改动。',
    ['点击镜像区域查看校验和错误提示，再了解如何选择目标设备。', '浏览分区和文件系统选项，导览期间不要执行最后的写入操作。'],
  ),
  'togo-page': _GuideContent(
    'To Go 用于创建便携式 Windows 工作区。写入前会检查 Windows 镜像元数据、固件布局、可用选项、驱动和目标磁盘。Linux 便携工作区将在后续版本提供；当前需要 Linux 启动设备时，请使用 Linux 安装盘。',
    ['选择 Windows ISO，查看识别出的版本和兼容性提示。', '打开高级选项，阅读固件、文件系统和驱动说明，但不要开始制作。'],
  ),
  'benchmark-page': _GuideContent(
    '磁盘测试会以清晰的进度状态测量顺序和随机负载。结果会绑定磁盘身份保存，之后可以比较不同设备，而不是只看一个孤立数字。',
    ['选择测试方案，查看负载选择器和实时折线图。', '打开测试历史，了解对比、导出、筛选和删除如何配合使用。'],
  ),
  'benchmark-history': _GuideContent(
    '测试历史是保存测量结果的工作区。你可以选择不同磁盘的多条记录进行对比，导出带有明确文件名的报告，或只删除选中的记录。',
    ['选择两个不同设备的记录，打开对比视图。', '体验导出菜单，查看报告中的设备身份、测试数据和折线图。'],
  ),
  'disktools-page': _GuideContent(
    '磁盘工具集中放置需要谨慎操作的维护功能。概览会先说明每个工具的影响，再带你进入磁盘诊断或启动修复，并明确安全边界。',
    ['打开工具卡片，阅读前置条件和确认步骤。', '进入二级页面后使用返回导航，导览会继续跟随当前栏目。'],
  ),
  'disk-diagnostics': _GuideContent(
    '磁盘诊断展示健康度、温度、固件和设备身份等信息。项目会结合 Windows 存储接口和辅助程序读取数据；桥接器能提供时也会显示，无法读取的字段会明确标记。',
    ['浏览健康摘要和设备详情，不需要执行任何修复。', '连接或断开磁盘后体验刷新设备列表。'],
  ),
  'boot-repair': _GuideContent(
    'BCD / EFI 启动修复用于检查和修复启动项。真正修改前会创建回滚点，并将扫描、预览、应用拆成独立步骤。',
    ['体验扫描和预览页面，查看将要修改的内容。', '停留在应用前一步，导览不会修改启动数据。'],
  ),
  'logs-page': _GuideContent(
    '日志中心把长时间任务整理成可追溯的时间线。筛选、级别标识、详情和导出功能可以帮助你定位问题，而不需要复制整个日志目录。',
    ['按级别筛选并打开一条日志查看结构化详情。', '使用右侧菜单复制或导出当前筛选范围。'],
  ),
  'ai-page': _GuideContent(
    'AI 助手可以根据你选择的测试记录、镜像信息和制作状态给出解释。端点、模型和密钥由你控制，服务无法连接时也会明确说明。',
    ['打开服务设置，查看端点和模型，但不必立即发送请求。', '输入一个简短问题，或附加选中的磁盘测试记录，查看解释结果。'],
  ),
  'tools-page': _GuideContent(
    '工具页提供支撑主流程的独立小工具，减少不必要的层级。每个工具都有自己的输入和结果区域，可能产生改动的操作会要求明确确认。',
    ['打开一个工具，浏览它的输入和输出区域。', '返回工具网格，观察左侧主导航仍然可以使用。'],
  ),
  'settings-page': _GuideContent(
    '设置是个性化应用的地方：外观、语言、更新源、AI 服务、权限和本导览都按清晰的分组排列。设置会立即生效并保存在本机。',
    ['切换视觉样式或语言，观察界面无需重启即可适配。', '在应用导览中重新查看完整导览，或直接回看单个栏目。'],
  ),
};

const _guideZhTw = <String, _GuideContent>{
  'home-page': _GuideContent(
    '首頁把最常用的操作集中在一起：快速開始、最近映像與儲存裝置概覽。它是可以直接使用的工作區，不需要先完成複雜設定。',
    ['開啟最近映像或快速開始卡片，體驗常用操作的一鍵入口。', '瀏覽儲存裝置概覽，觀察各卡片獨立載入和更新。'],
  ),
  'images-page': _GuideContent(
    '映像中心用於在寫入之前了解映像。詳細頁會說明版本、語言、大小、下載管道，以及已知時的校驗值和相容性提醒。',
    ['選擇一個分類，開啟映像詳細資料並閱讀適用性說明。', '可以體驗下載選項，但導覽不會寫入任何磁碟。'],
  ),
  'creator-page': _GuideContent(
    '安裝媒體製作會分階段引導你建立啟動碟。映像區域負責校驗 ISO，目標區域保護你避免選錯磁碟，最後的確認頁會列出即將發生的變更。',
    ['點擊映像區域查看校驗和錯誤提示，再了解如何選擇目標裝置。', '瀏覽分割區和檔案系統選項，導覽期間不要執行最後的寫入操作。'],
  ),
  'togo-page': _GuideContent(
    'To Go 用於建立可攜式 Windows 工作空間。寫入前會檢查 Windows 映像中繼資料、韌體配置、可用選項、驅動程式和目標磁碟。Linux 可攜式工作空間將於後續版本提供；目前需要 Linux 開機裝置時，請使用 Linux 安裝碟。',
    ['選擇 Windows ISO，查看識別出的版本和相容性提示。', '開啟進階選項，閱讀韌體、檔案系統和驅動程式說明，但不要開始製作。'],
  ),
  'benchmark-page': _GuideContent(
    '磁碟測試會以清晰的進度狀態測量順序和隨機負載。結果會繫結磁碟身分保存，之後可以比較不同裝置，而不是只看一個孤立數字。',
    ['選擇測試方案，查看負載選擇器和即時折線圖。', '開啟測試歷史，了解比較、匯出、篩選和刪除如何配合使用。'],
  ),
  'benchmark-history': _GuideContent(
    '測試歷史是保存測量結果的工作區。你可以選擇不同磁碟的多筆記錄進行比較，匯出帶有明確檔名的報告，或只刪除選取的記錄。',
    ['選擇兩個不同裝置的記錄，開啟比較檢視。', '體驗匯出選單，查看報告中的裝置身分、測試資料和折線圖。'],
  ),
  'disktools-page': _GuideContent(
    '磁碟工具集中放置需要謹慎操作的維護功能。概覽會先說明每個工具的影響，再帶你進入磁碟診斷或啟動修復，並明確安全邊界。',
    ['開啟工具卡片，閱讀前置條件和確認步驟。', '進入次級頁面後使用返回導覽，導覽會繼續跟隨目前欄目。'],
  ),
  'disk-diagnostics': _GuideContent(
    '磁碟診斷展示健康度、溫度、韌體和裝置身分等資訊。專案會結合 Windows 儲存介面和輔助程式讀取資料；橋接器能提供時也會顯示，無法讀取的欄位會明確標記。',
    ['瀏覽健康摘要和裝置詳細資料，不需要執行任何修復。', '連接或斷開磁碟後體驗重新整理裝置列表。'],
  ),
  'boot-repair': _GuideContent(
    'BCD / EFI 啟動修復用於檢查和修復啟動項目。真正修改前會建立回復點，並將掃描、預覽、套用拆成獨立步驟。',
    ['體驗掃描和預覽頁面，查看將要修改的內容。', '停留在套用前一步，導覽不會修改啟動資料。'],
  ),
  'logs-page': _GuideContent(
    '記錄中心把長時間任務整理成可追溯的時間線。篩選、級別標示、詳細資料和匯出功能可以幫助你定位問題，而不需要複製整個記錄資料夾。',
    ['按級別篩選並開啟一條記錄查看結構化詳細資料。', '使用右側選單複製或匯出目前篩選範圍。'],
  ),
  'ai-page': _GuideContent(
    'AI 助手可以根據你選擇的測試記錄、映像資訊和製作狀態給出解釋。端點、模型和金鑰由你控制，服務無法連線時也會明確說明。',
    ['開啟服務設定，查看端點和模型，但不必立即傳送請求。', '輸入一個簡短問題，或附加選取的磁碟測試記錄，查看解釋結果。'],
  ),
  'tools-page': _GuideContent(
    '工具頁提供支援主流程的獨立小工具，減少不必要的層級。每個工具都有自己的輸入和結果區域，可能產生變更的操作會要求明確確認。',
    ['開啟一個工具，瀏覽它的輸入和輸出區域。', '返回工具網格，觀察左側主導覽仍然可以使用。'],
  ),
  'settings-page': _GuideContent(
    '設定是個人化應用程式的地方：外觀、語言、更新來源、AI 服務、權限和本導覽都按清晰的分組排列。設定會立即生效並保存在本機。',
    ['切換視覺樣式或語言，觀察介面無需重新啟動即可適配。', '在應用程式導覽中重新查看完整導覽，或直接回看單個欄目。'],
  ),
};

String _copy(BuildContext context, String key) {
  final code = normalizeLocaleCode(
    localeCodeFromLocale(Localizations.localeOf(context)),
  );
  final copy = switch (code) {
    'zh' => _zhCopy,
    'zh_TW' => _zhTwCopy,
    'fr' => _frCopy,
    'de' => _deCopy,
    'es' => _esCopy,
    'pt' => _ptCopy,
    'ru' => _ruCopy,
    'ar' => _arCopy,
    'ko' => _koCopy,
    'ja' => _jaCopy,
    _ => _enCopy,
  };
  return copy[key] ?? _enCopy[key] ?? '';
}

String onboardingCopy(BuildContext context, String key) => _copy(context, key);

const _enCopy = <String, String>{
  'title': 'Quick tour',
  'navigationHint':
      'Select the highlighted navigation item to open this section. You can also use the button below.',
  'close': 'Close tour',
  'endTour': 'End tour',
  'endTourQuestion': 'End this tour?',
  'endTourSwitchMessage':
      'You opened another section. Leave this tour and return to the app?',
  'skipSection': 'Skip this section',
  'open': 'Open',
  'back': 'Previous',
  'next': 'Next',
  'done': 'Start using',
  'startExploring': 'Start exploring',
  'openAndExplore': 'Open & explore',
  'exploringHint': 'You can browse this page freely',
  'tryLabel': 'Good places to start',
  'genericExplore1':
      'Browse the controls and details that are relevant to this section.',
  'genericExplore2':
      'The tour will not start a destructive operation without your explicit confirmation.',
  'switchTitle': 'Switch this tour?',
  'stayTour': 'Stay with current tour',
  'continueTour': 'Continue tour',
  'switchTour': 'Switch tour',
  'replayTitle': 'App tour',
  'replayDescription': 'Review the complete tour or choose one section.',
  'replayAll': 'Full tour',
  'replaySection': 'Choose section',
  'settingsDescription':
      'Customize appearance, AI services, updates, language, and tour preferences.',
};

const _zhCopy = <String, String>{
  'title': '快速导览',
  'navigationHint': '点击高亮的左侧菜单打开本栏目，也可以使用下方按钮继续。',
  'close': '关闭导览',
  'endTour': '结束导览',
  'endTourQuestion': '结束本次导览？',
  'endTourSwitchMessage': '你打开了其他栏目。要结束当前导览并返回正常使用吗？',
  'skipSection': '跳过本栏目',
  'open': '打开',
  'back': '上一步',
  'next': '下一步',
  'done': '开始使用',
  'startExploring': '开始体验',
  'openAndExplore': '打开并体验',
  'exploringHint': '现在可以自由浏览本页面',
  'tryLabel': '可以先试试',
  'genericExplore1': '浏览本栏目中与你当前任务相关的控件和详情。',
  'genericExplore2': '没有你的明确确认，导览不会开始任何破坏性操作。',
  'switchTitle': '切换到这个导览？',
  'stayTour': '继续当前导览',
  'continueTour': '继续导览',
  'switchTour': '切换导览',
  'replayTitle': '应用导览',
  'replayDescription': '重新查看完整导览，或只查看某个栏目。',
  'replayAll': '完整导览',
  'replaySection': '选择栏目',
  'settingsDescription': '在这里调整外观、AI 服务、更新、语言和导览设置。',
};

const _zhTwCopy = <String, String>{
  'title': '快速導覽',
  'navigationHint': '點擊高亮的左側選單開啟本欄目，也可以使用下方按鈕繼續。',
  'close': '關閉導覽',
  'endTour': '結束導覽',
  'endTourQuestion': '結束這次導覽？',
  'endTourSwitchMessage': '你開啟了其他欄目。要結束目前導覽並返回正常使用嗎？',
  'skipSection': '略過本欄目',
  'open': '開啟',
  'back': '上一步',
  'next': '下一步',
  'done': '開始使用',
  'startExploring': '開始體驗',
  'openAndExplore': '開啟並體驗',
  'exploringHint': '現在可以自由瀏覽本頁面',
  'tryLabel': '可以先試試',
  'genericExplore1': '瀏覽本欄目中與目前任務相關的控制項和詳細資料。',
  'genericExplore2': '沒有你的明確確認，導覽不會開始任何破壞性操作。',
  'switchTitle': '切換到這個導覽？',
  'stayTour': '繼續目前導覽',
  'continueTour': '繼續導覽',
  'switchTour': '切換導覽',
  'replayTitle': '應用程式導覽',
  'replayDescription': '重新查看完整導覽，或只查看某個欄目。',
  'replayAll': '完整導覽',
  'replaySection': '選擇欄目',
  'settingsDescription': '在這裡調整外觀、AI 服務、更新、語言和導覽設定。',
};

const _frCopy = <String, String>{
  'title': 'Visite guidée',
  'navigationHint':
      'Sélectionnez l’élément mis en évidence pour ouvrir cette section, ou utilisez le bouton ci-dessous.',
  'close': 'Fermer la visite',
  'endTour': 'Terminer la visite',
  'endTourQuestion': 'Terminer cette visite ?',
  'endTourSwitchMessage':
      'Vous avez ouvert une autre section. Terminer cette visite et revenir à l’application ?',
  'skipSection': 'Ignorer cette section',
  'open': 'Ouvrir',
  'back': 'Précédent',
  'next': 'Suivant',
  'done': 'Commencer',
  'startExploring': 'Commencer l’exploration',
  'openAndExplore': 'Ouvrir et explorer',
  'exploringHint': 'Vous pouvez parcourir cette page librement',
  'tryLabel': 'Premiers essais',
  'genericExplore1':
      'Parcourez les commandes et les détails utiles dans cette section.',
  'genericExplore2':
      'Aucune opération destructive ne démarre sans votre confirmation explicite.',
  'switchTitle': 'Changer de visite ?',
  'stayTour': 'Garder la visite actuelle',
  'continueTour': 'Continuer la visite',
  'switchTour': 'Changer de visite',
  'replayTitle': 'Visite de l’application',
  'replayDescription': 'Revoir toute la visite ou choisir une section.',
  'replayAll': 'Visite complète',
  'replaySection': 'Choisir une section',
  'settingsDescription':
      'Personnalisez l’apparence, les services IA, les mises à jour, la langue et les préférences de visite.',
};

const _deCopy = <String, String>{
  'title': 'Schnellführung',
  'navigationHint':
      'Wählen Sie den hervorgehobenen Menüpunkt oder verwenden Sie die Schaltfläche unten.',
  'close': 'Führung schließen',
  'endTour': 'Führung beenden',
  'endTourQuestion': 'Diese Führung beenden?',
  'endTourSwitchMessage':
      'Sie haben einen anderen Bereich geöffnet. Diese Führung beenden und zur App zurückkehren?',
  'skipSection': 'Diesen Bereich überspringen',
  'open': 'Öffnen',
  'back': 'Zurück',
  'next': 'Weiter',
  'done': 'Starten',
  'startExploring': 'Erkunden',
  'openAndExplore': 'Öffnen und erkunden',
  'exploringHint': 'Sie können diese Seite frei durchsuchen',
  'tryLabel': 'Zum Ausprobieren',
  'genericExplore1':
      'Sehen Sie sich die relevanten Steuerelemente und Details dieses Bereichs an.',
  'genericExplore2':
      'Destruktive Aktionen starten erst nach Ihrer ausdrücklichen Bestätigung.',
  'switchTitle': 'Führung wechseln?',
  'stayTour': 'Aktuelle Führung behalten',
  'continueTour': 'Führung fortsetzen',
  'switchTour': 'Führung wechseln',
  'replayTitle': 'App-Führung',
  'replayDescription':
      'Die vollständige Führung oder einen Bereich erneut ansehen.',
  'replayAll': 'Vollständige Führung',
  'replaySection': 'Bereich auswählen',
  'settingsDescription':
      'Darstellung, KI-Dienste, Updates, Sprache und Führungsoptionen anpassen.',
};

const _esCopy = <String, String>{
  'title': 'Guía rápida',
  'navigationHint':
      'Seleccione el elemento resaltado del menú o use el botón inferior.',
  'close': 'Cerrar guía',
  'endTour': 'Finalizar guía',
  'endTourQuestion': '¿Finalizar esta guía?',
  'endTourSwitchMessage':
      'Ha abierto otra sección. ¿Finalizar esta guía y volver a la aplicación?',
  'skipSection': 'Omitir esta sección',
  'open': 'Abrir',
  'back': 'Anterior',
  'next': 'Siguiente',
  'done': 'Empezar',
  'startExploring': 'Empezar a explorar',
  'openAndExplore': 'Abrir y explorar',
  'exploringHint': 'Puede explorar esta página libremente',
  'tryLabel': 'Para probar',
  'genericExplore1':
      'Explore los controles y detalles relevantes de esta sección.',
  'genericExplore2':
      'Ninguna operación destructiva comienza sin su confirmación explícita.',
  'switchTitle': '¿Cambiar de guía?',
  'stayTour': 'Mantener la guía actual',
  'continueTour': 'Continuar la guía',
  'switchTour': 'Cambiar de guía',
  'replayTitle': 'Guía de la aplicación',
  'replayDescription': 'Revise toda la guía o elija una sección.',
  'replayAll': 'Guía completa',
  'replaySection': 'Elegir sección',
  'settingsDescription':
      'Personalice la apariencia, los servicios de IA, las actualizaciones, el idioma y la guía.',
};

const _ptCopy = <String, String>{
  'title': 'Visita rápida',
  'navigationHint': 'Selecione o item destacado no menu ou use o botão abaixo.',
  'close': 'Fechar visita',
  'endTour': 'Encerrar visita',
  'endTourQuestion': 'Encerrar esta visita?',
  'endTourSwitchMessage':
      'Você abriu outra seção. Encerrar esta visita e voltar ao aplicativo?',
  'skipSection': 'Ignorar esta seção',
  'open': 'Abrir',
  'back': 'Anterior',
  'next': 'Avançar',
  'done': 'Começar',
  'startExploring': 'Começar a explorar',
  'openAndExplore': 'Abrir e explorar',
  'exploringHint': 'Você pode navegar livremente nesta página',
  'tryLabel': 'Experimente',
  'genericExplore1': 'Explore os controles e detalhes relevantes desta seção.',
  'genericExplore2':
      'Nenhuma operação destrutiva começa sem sua confirmação explícita.',
  'switchTitle': 'Trocar de visita?',
  'stayTour': 'Manter a visita atual',
  'continueTour': 'Continuar visita',
  'switchTour': 'Trocar visita',
  'replayTitle': 'Visita do aplicativo',
  'replayDescription': 'Revise a visita completa ou escolha uma seção.',
  'replayAll': 'Visita completa',
  'replaySection': 'Escolher seção',
  'settingsDescription':
      'Personalize aparência, serviços de IA, atualizações, idioma e preferências da visita.',
};

const _ruCopy = <String, String>{
  'title': 'Быстрый обзор',
  'navigationHint':
      'Выберите выделенный пункт меню или используйте кнопку ниже.',
  'close': 'Закрыть обзор',
  'endTour': 'Завершить обзор',
  'endTourQuestion': 'Завершить этот обзор?',
  'endTourSwitchMessage':
      'Вы открыли другой раздел. Завершить обзор и вернуться в приложение?',
  'skipSection': 'Пропустить раздел',
  'open': 'Открыть',
  'back': 'Назад',
  'next': 'Далее',
  'done': 'Начать',
  'startExploring': 'Начать изучение',
  'openAndExplore': 'Открыть и изучить',
  'exploringHint': 'Эту страницу можно свободно просматривать',
  'tryLabel': 'Что попробовать',
  'genericExplore1':
      'Просмотрите элементы управления и сведения этого раздела.',
  'genericExplore2':
      'Деструктивная операция не начнётся без явного подтверждения.',
  'switchTitle': 'Сменить обзор?',
  'stayTour': 'Оставить текущий обзор',
  'continueTour': 'Продолжить обзор',
  'switchTour': 'Сменить обзор',
  'replayTitle': 'Обзор приложения',
  'replayDescription': 'Повторите весь обзор или выберите раздел.',
  'replayAll': 'Полный обзор',
  'replaySection': 'Выбрать раздел',
  'settingsDescription':
      'Настройте внешний вид, службы ИИ, обновления, язык и параметры обзора.',
};

const _arCopy = <String, String>{
  'title': 'جولة سريعة',
  'navigationHint': 'اختر عنصر التنقل المميز أو استخدم الزر أدناه.',
  'close': 'إغلاق الجولة',
  'endTour': 'إنهاء الجولة',
  'endTourQuestion': 'هل تريد إنهاء هذه الجولة؟',
  'endTourSwitchMessage':
      'لقد فتحت قسمًا آخر. هل تريد إنهاء الجولة والعودة إلى التطبيق؟',
  'skipSection': 'تخطي هذا القسم',
  'open': 'فتح',
  'back': 'السابق',
  'next': 'التالي',
  'done': 'بدء الاستخدام',
  'startExploring': 'بدء الاستكشاف',
  'openAndExplore': 'فتح واستكشاف',
  'exploringHint': 'يمكنك تصفح هذه الصفحة بحرية',
  'tryLabel': 'اقتراحات للتجربة',
  'genericExplore1': 'استعرض عناصر التحكم والتفاصيل المهمة في هذا القسم.',
  'genericExplore2': 'لن تبدأ أي عملية مدمرة من دون تأكيدك الصريح.',
  'switchTitle': 'هل تريد تبديل الجولة؟',
  'stayTour': 'البقاء في الجولة الحالية',
  'continueTour': 'متابعة الجولة',
  'switchTour': 'تبديل الجولة',
  'replayTitle': 'جولة التطبيق',
  'replayDescription': 'راجع الجولة كاملة أو اختر قسمًا واحدًا.',
  'replayAll': 'الجولة الكاملة',
  'replaySection': 'اختيار قسم',
  'settingsDescription':
      'خصص المظهر وخدمات الذكاء الاصطناعي والتحديثات واللغة وتفضيلات الجولة.',
};

const _koCopy = <String, String>{
  'title': '빠른 둘러보기',
  'navigationHint': '강조된 탐색 항목을 선택하거나 아래 버튼을 사용하세요.',
  'close': '둘러보기 닫기',
  'endTour': '둘러보기 종료',
  'endTourQuestion': '이 둘러보기를 종료할까요?',
  'endTourSwitchMessage': '다른 섹션을 열었습니다. 둘러보기를 종료하고 앱으로 돌아갈까요?',
  'skipSection': '이 섹션 건너뛰기',
  'open': '열기',
  'back': '이전',
  'next': '다음',
  'done': '사용 시작',
  'startExploring': '탐색 시작',
  'openAndExplore': '열고 탐색',
  'exploringHint': '이 페이지를 자유롭게 둘러볼 수 있습니다',
  'tryLabel': '먼저 사용해 보기',
  'genericExplore1': '이 섹션의 관련 컨트롤과 세부 정보를 살펴보세요.',
  'genericExplore2': '명시적으로 확인하기 전에는 파괴적인 작업이 시작되지 않습니다.',
  'switchTitle': '둘러보기를 전환할까요?',
  'stayTour': '현재 둘러보기 유지',
  'continueTour': '둘러보기 계속',
  'switchTour': '둘러보기 전환',
  'replayTitle': '앱 둘러보기',
  'replayDescription': '전체 둘러보기를 다시 보거나 섹션을 선택하세요.',
  'replayAll': '전체 둘러보기',
  'replaySection': '섹션 선택',
  'settingsDescription': '화면, AI 서비스, 업데이트, 언어 및 둘러보기 설정을 사용자 지정합니다.',
};

const _jaCopy = <String, String>{
  'title': 'クイックツアー',
  'navigationHint': '強調表示されたナビゲーション項目を選択するか、下のボタンを使用してください。',
  'close': 'ツアーを閉じる',
  'endTour': 'ツアーを終了',
  'endTourQuestion': 'このツアーを終了しますか？',
  'endTourSwitchMessage': '別のセクションを開きました。ツアーを終了してアプリに戻りますか？',
  'skipSection': 'このセクションをスキップ',
  'open': '開く',
  'back': '戻る',
  'next': '次へ',
  'done': '使い始める',
  'startExploring': '探索を開始',
  'openAndExplore': '開いて探索',
  'exploringHint': 'このページを自由に確認できます',
  'tryLabel': '試してみること',
  'genericExplore1': 'このセクションに関係する操作と詳細を確認してください。',
  'genericExplore2': '明示的に確認するまで破壊的な操作は開始されません。',
  'switchTitle': 'ツアーを切り替えますか？',
  'stayTour': '現在のツアーを続ける',
  'continueTour': 'ツアーを続ける',
  'switchTour': 'ツアーを切り替え',
  'replayTitle': 'アプリツアー',
  'replayDescription': '完全なツアーを再表示するか、セクションを選択します。',
  'replayAll': '完全なツアー',
  'replaySection': 'セクションを選択',
  'settingsDescription': '外観、AI サービス、更新、言語、ツアーの設定を変更します。',
};

class _SpotlightClipper extends CustomClipper<Path> {
  const _SpotlightClipper(this.target);

  final Rect? target;

  @override
  Path getClip(Size size) {
    final path = Path()..addRect(Offset.zero & size);
    final target = this.target;
    if (target != null) {
      path
        ..addRRect(RRect.fromRectAndRadius(target, const Radius.circular(12)))
        ..fillType = PathFillType.evenOdd;
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _SpotlightClipper oldClipper) =>
      oldClipper.target != target;
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.target,
    required this.pulse,
    required this.overlayColor,
    required this.accent,
  });

  final Rect? target;
  final double pulse;
  final Color overlayColor;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRect(Offset.zero & size);
    final target = this.target;
    if (target != null) {
      path
        ..addRRect(RRect.fromRectAndRadius(target, const Radius.circular(12)))
        ..fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(path, Paint()..color = overlayColor);

    if (target != null) {
      final expanded = target.inflate(2 + pulse * 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(expanded, const Radius.circular(14)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = accent.withValues(alpha: 0.72 - pulse * 0.22),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.target != target ||
      oldDelegate.pulse != pulse ||
      oldDelegate.overlayColor != overlayColor ||
      oldDelegate.accent != accent;
}
