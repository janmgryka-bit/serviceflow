import '../models/diagnostic_profile.dart';

/// Offline fallbacks when Groq is unavailable or returns nothing useful.
abstract final class DiagnosticTemplates {
  static String normalizeDeviceKind(String deviceCategory) {
    final s = deviceCategory.trim().toLowerCase();
    if (s.contains('phone') || s.contains('iphone') || s.contains('android phone')) {
      return 'phone';
    }
    if (s.contains('tablet') || s.contains('ipad')) {
      return 'tablet';
    }
    return 'laptop';
  }

  static DiagnosticProfile forDeviceCategory(String deviceCategory) {
    switch (normalizeDeviceKind(deviceCategory)) {
      case 'phone':
        return _genericPhone();
      case 'tablet':
        return _genericTablet();
      default:
        return _genericLaptop();
    }
  }

  static DiagnosticProfile _genericLaptop() {
    return const DiagnosticProfile(
      mainPowerRails: [
        MainPowerRail(
          name: 'Adapter / VIN',
          description: 'Input from barrel or USB-C PD rail before main conversion',
          measurementHint: 'V: adapter present; Ω: short check',
        ),
        MainPowerRail(
          name: '+3VALW / +3VLP',
          description: 'Always-on / standby 3.3 V (EC, PCH partial)',
          measurementHint: 'Expect ~3.3 V in S0/S3',
        ),
        MainPowerRail(
          name: '+5VALW',
          description: '5 V always-on for USB, some loads',
          measurementHint: '~5 V when enabled',
        ),
        MainPowerRail(
          name: 'VCORE (CPU)',
          description: 'Core buck output to CPU',
          measurementHint: 'SVID/IMVP — varies with load',
        ),
        MainPowerRail(
          name: 'DRAM VDDQ',
          description: 'Memory supply',
          measurementHint: 'DDR3/DDR4 typical 1.35–1.5 V',
        ),
        MainPowerRail(
          name: 'PCH / chipset core',
          description: '1.0 V–1.8 V typ. PCH rail',
          measurementHint: 'Check schematic net name on your board',
        ),
      ],
      commonFaults: [
        'No power / dead short on 19 V input',
        'Power LED on but no POST — missing S3/S0 rails',
        'Random shutdown — thermal or VCORE instability',
        'USB/LAN dead — missing +3V/+5V derived rails',
        'Battery not charging — ACFET / PQ or fuel gauge path',
      ],
      startupSequence: [
        StartupStep(
          signal: 'Adapter present / ACIN',
          description: 'Verify input voltage and current limit',
        ),
        StartupStep(
          signal: '+3VLP / +3VALW',
          description: 'First standby rails from PMIC or discrete LDOs',
        ),
        StartupStep(
          signal: 'RSMRST# / PM_RESET',
          description: 'PCH out of reset, sequencing OK',
        ),
        StartupStep(
          signal: 'SLP_S4# / SLP_S3#',
          description: 'Sleep states as you press power',
        ),
        StartupStep(
          signal: 'CPU VCORE enable',
          description: 'VR_ON or equivalent — core rail comes up',
        ),
      ],
      confidence: 'low',
      source: DiagnosticProfileSource.genericTemplate,
    );
  }

  static DiagnosticProfile _genericPhone() {
    return const DiagnosticProfile(
      mainPowerRails: [
        MainPowerRail(
          name: 'VBAT / BATTERY',
          description: 'Cell or connector voltage',
          measurementHint: '3.7–4.4 V typical',
        ),
        MainPowerRail(
          name: 'VDD_MAIN / VDD_BOOST',
          description: 'Main system rail from PMIC',
          measurementHint: 'Often 3.8–4.5 V domain',
        ),
        MainPowerRail(
          name: 'VDD_CPU / SOC',
          description: 'SoC core supply',
          measurementHint: 'Low voltage, high current',
        ),
        MainPowerRail(
          name: 'VDD_GPU / MEM',
          description: 'Graphics / memory rail if separate',
        ),
        MainPowerRail(
          name: 'LDO peripherals',
          description: '1.8 V / 2.8 V camera, NFC, etc.',
        ),
      ],
      commonFaults: [
        'No boot — PMIC or battery detect',
        'Boot loop — CPU power collapse',
        'No display — backlight boost / Tigris line',
        'No charge — Tristar / Tigris / dock flex',
        'Baseband / RF — separate buck tree; check shorts',
      ],
      startupSequence: [
        StartupStep(
          signal: 'Battery / VBUS',
          description: 'Confirm fuel gauge and charger handshake',
        ),
        StartupStep(
          signal: 'PMIC power-on sequence',
          description: 'First enables after button or auto-boot',
        ),
        StartupStep(
          signal: 'VDD_MAIN',
          description: 'Main distribution up',
        ),
        StartupStep(
          signal: 'CPU reset release',
          description: 'AP reset line timing',
        ),
        StartupStep(
          signal: 'Clocks (32 kHz / BB)',
          description: 'Reference oscillators running',
        ),
      ],
      confidence: 'low',
      source: DiagnosticProfileSource.genericTemplate,
    );
  }

  static DiagnosticProfile _genericTablet() {
    return const DiagnosticProfile(
      mainPowerRails: [
        MainPowerRail(
          name: 'VBAT / DCIN',
          description: 'Battery or dock input',
        ),
        MainPowerRail(
          name: 'System 3V3 / 5V',
          description: 'Main PMIC outputs',
        ),
        MainPowerRail(
          name: 'SoC core',
          description: 'Application processor rail',
        ),
        MainPowerRail(
          name: 'DRAM',
          description: 'Memory supply',
        ),
        MainPowerRail(
          name: 'Display / backlight',
          description: 'Boost for panel (if separate)',
        ),
      ],
      commonFaults: [
        'No power — dock/charge port or PMIC',
        'Stuck logo — eMMC/UFS or RAM',
        'Touch dead — digitizer supply or connector',
        'No WiFi — RF section or enable GPIO',
      ],
      startupSequence: [
        StartupStep(
          signal: 'Input power',
          description: 'Adapter or battery present',
        ),
        StartupStep(
          signal: 'PMIC sequence',
          description: 'Ordered enables',
        ),
        StartupStep(
          signal: 'SoC power good',
          description: 'Core rails stable',
        ),
        StartupStep(
          signal: 'Reset / clock',
          description: 'Out of reset, clocks OK',
        ),
      ],
      confidence: 'low',
      source: DiagnosticProfileSource.genericTemplate,
    );
  }
}
