import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

import 'data/movement_repository.dart';
import 'data/bank_observation_repository.dart';
import 'design/material_symbol.dart';
import 'domain/currency.dart';
import 'domain/money_movement.dart';
import 'domain/movement_totals.dart';
import 'services/whatsapp_contacts.dart';
import 'services/movement_export_service.dart';
import 'services/movement_filter.dart';
import 'services/bank_notification_parser.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.repository});

  final MovementRepository? repository;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final Future<MovementRepository> _repository;

  @override
  void initState() {
    super.initState();
    final providedRepository = widget.repository;
    _repository = providedRepository == null
        ? MovementRepository.openForCurrentPlatform()
        : Future.value(providedRepository);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BRUGES FINANZAS 360',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: FutureBuilder<MovementRepository>(
        future: _repository,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StorageError(error: snapshot.error!);
          }
          if (!snapshot.hasData) return const _SplashScreen();
          return _FinanceHome(repository: snapshot.data!);
        },
      ),
    );
  }
}

ThemeData _buildTheme() {
  const emerald = Color(0xFF075B43);
  final scheme = ColorScheme.fromSeed(
    seedColor: emerald,
    brightness: Brightness.light,
    surface: const Color(0xFFF8F7F2),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF8F7F2),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF8F7F2),
      foregroundColor: Color(0xFF18201C),
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE8E9E2)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF4F5F0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class _FinanceHome extends StatefulWidget {
  const _FinanceHome({required this.repository});

  final MovementRepository repository;

  @override
  State<_FinanceHome> createState() => _FinanceHomeState();
}

class _FinanceHomeState extends State<_FinanceHome>
    with WidgetsBindingObserver {
  static const _exportChannel = MethodChannel('com.bruges.finanzas360/export');
  static const _notificationChannel = MethodChannel(
    'com.bruges.finanzas360/notifications',
  );
  static const _bankNotifications = EventChannel(
    'com.bruges.finanzas360/bank-notifications',
  );
  int _selectedIndex = 0;
  late Future<List<MoneyMovement>> _movements;
  late final Future<BankObservationRepository> _observations;
  StreamSubscription<dynamic>? _notificationSubscription;
  Set<String> _enabledBankPackages = <String>{};
  bool _hasNotificationAccess = false;

  static const _sections = <_SectionData>[
    _SectionData('Resumen', 'home'),
    _SectionData('Movimientos', 'receipt_long'),
    _SectionData('Reportes', 'bar_chart'),
    _SectionData('Configuración', 'settings'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _movements = widget.repository.listMovements();
    final dataDirectory = widget.repository.dataDirectory;
    _observations = dataDirectory == null
        ? Future.value(BankObservationRepository.inMemory())
        : BankObservationRepository.open(dataDirectory);
    if (Platform.isAndroid) {
      _notificationSubscription = _bankNotifications
          .receiveBroadcastStream()
          .listen(
            (event) => unawaited(_processBankObservation(event)),
            onError: (_) {},
          );
      unawaited(_loadBankSettings());
      unawaited(_drainBankNotificationQueue());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      unawaited(_loadBankSettings());
      unawaited(_drainBankNotificationQueue());
    }
  }

  Future<void> _processBankObservation(dynamic event) async {
    if (event is! Map) return;
    final BankNotificationObservation observation;
    try {
      observation = BankNotificationObservation.fromJson(
        Map<String, Object?>.from(event),
      );
    } on Object {
      return;
    }
    if (observation.isReadyForAutomaticRegistration) {
      await widget.repository.addMovement(observation.toMovement());
      if (mounted) _reload();
    } else {
      await (await _observations).add(observation);
    }
    try {
      await _notificationChannel.invokeMethod<bool>('ackBankObservations', {
        'ids': [observation.id],
      });
    } on PlatformException {
      // If acknowledgement fails the native queue retries; the ledger is
      // idempotent by observation ID.
    } on MissingPluginException {
      // Non-Android test/runtime.
    }
  }

  Future<void> _drainBankNotificationQueue() async {
    try {
      final rows = await _notificationChannel.invokeMethod<List<dynamic>>(
        'pendingBankObservations',
      );
      for (final row in rows ?? const <dynamic>[]) {
        await _processBankObservation(row);
      }
    } on PlatformException {
      // The native queue remains durable and will be retried on next launch.
    } on MissingPluginException {
      // Non-Android test/runtime.
    }
  }

  Future<void> _loadBankSettings() async {
    try {
      final packages = await _notificationChannel.invokeMethod<List<dynamic>>(
        'getEnabledBankPackages',
      );
      final hasAccess = await _notificationChannel.invokeMethod<bool>(
        'hasListenerAccess',
      );
      if (!mounted) return;
      setState(() {
        _enabledBankPackages = (packages ?? const <dynamic>[])
            .whereType<String>()
            .toSet();
        _hasNotificationAccess = hasAccess ?? false;
      });
    } on PlatformException {
      // Keep the safe default: no bank source enabled.
    } on MissingPluginException {
      // Non-Android test/runtime.
    }
  }

  Future<void> _configureBankDetection() async {
    final selected = Set<String>.of(_enabledBankPackages);
    final saved = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const MaterialSymbol('shield'),
          title: const Text('Detección externa'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Elige las apps cuyos avisos quieres procesar. Solo se guardan campos estructurados; el texto íntegro no se conserva. Los paquetes están verificados en Google Play, pero los formatos reales de avisos aún requieren validación por entidad. Android exige permiso explícito y puede suspender el servicio.',
                  ),
                  const SizedBox(height: 10),
                  for (final entry in bankNotificationPackages.entries)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.value),
                      value: selected.contains(entry.key),
                      onChanged: (enabled) => setDialogState(() {
                        if (enabled == true) {
                          selected.add(entry.key);
                        } else {
                          selected.remove(entry.key);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('Guardar selección'),
            ),
          ],
        ),
      ),
    );
    if (saved == null || !mounted) return;
    try {
      final persisted = await _notificationChannel.invokeMethod<List<dynamic>>(
        'setEnabledBankPackages',
        {'packages': saved.toList()},
      );
      if (!mounted) return;
      setState(() {
        _enabledBankPackages = (persisted ?? const <dynamic>[])
            .whereType<String>()
            .toSet();
      });
      if (_enabledBankPackages.isNotEmpty && !_hasNotificationAccess) {
        final openSettings = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const MaterialSymbol('notifications_active'),
            title: const Text('Autorizar acceso en Android'),
            content: const Text(
              'Android mostrará su propia pantalla de autorización. BRUGES solo recibirá notificaciones de las entidades elegidas.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Ahora no'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Abrir ajustes'),
              ),
            ],
          ),
        );
        if (openSettings == true) {
          await _notificationChannel.invokeMethod<bool>('openListenerSettings');
        }
      }
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se guardó la selección: ${error.message}')),
      );
    }
  }

  Future<void> _openNotificationSettings() async {
    try {
      await _notificationChannel.invokeMethod<bool>('openListenerSettings');
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se abrió el ajuste: ${error.message}')),
      );
    }
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _reload() {
    final updatedMovements = widget.repository.listMovements();
    setState(() {
      _movements = updatedMovements;
    });
  }

  Future<void> _createMovement() async {
    final movement = await showDialog<MoneyMovement>(
      context: context,
      builder: (context) => _MovementDialog(repository: widget.repository),
    );
    if (movement == null || !mounted) return;
    await widget.repository.addMovement(movement);
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Movimiento guardado en este dispositivo.')),
    );
  }

  Future<void> _exportMovements(
    List<MoneyMovement> movements, {
    required bool asCsv,
  }) async {
    try {
      final extension = asCsv ? 'csv' : 'json';
      final fileName = MovementExportService.fileName(extension);
      final contents = asCsv
          ? MovementExportService.toCsv(movements)
          : MovementExportService.toJson(movements);
      final String location;
      if (Platform.isAndroid) {
        final uri = await _exportChannel.invokeMethod<String>('saveExport', {
          'fileName': fileName,
          'mimeType': asCsv ? 'text/csv' : 'application/json',
          'contents': contents,
        });
        if (uri == null) return;
        location = uri;
      } else if (Platform.isWindows) {
        final profile = Platform.environment['USERPROFILE'];
        if (profile == null || profile.isEmpty) {
          throw StateError('No se encontró la carpeta del usuario de Windows.');
        }
        final directory = Directory(
          '$profile${Platform.pathSeparator}Documents${Platform.pathSeparator}BRUGES-FINANZAS-360-Exportaciones',
        );
        final file = asCsv
            ? await MovementExportService.writeCsv(movements, directory)
            : await MovementExportService.writeJson(movements, directory);
        location = file.path;
      } else {
        final dataDirectory = widget.repository.dataDirectory;
        if (dataDirectory == null) {
          throw StateError('La exportación no está disponible en memoria.');
        }
        final directory = Directory(
          '${dataDirectory.path}${Platform.pathSeparator}exports',
        );
        final file = asCsv
            ? await MovementExportService.writeCsv(movements, directory)
            : await MovementExportService.writeJson(movements, directory);
        location = file.path;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Archivo creado: $location')));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo exportar: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        final isCompact = constraints.maxWidth < 600;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: isCompact ? 0 : 16,
            leadingWidth: isCompact ? 45 : 56,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12, top: 7, bottom: 7),
              child: SvgPicture.asset(
                'assets/branding/bruges_finanzas_360.svg',
              ),
            ),
            title: const Text(
              'BRUGES FINANZAS 360',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _ConnectionChip(),
              ),
            ],
          ),
          body: Row(
            children: [
              if (isDesktop)
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedIndex = index),
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: const Color(0xFFF8F7F2),
                  destinations: [
                    for (final section in _sections)
                      NavigationRailDestination(
                        icon: MaterialSymbol(section.icon),
                        selectedIcon: MaterialSymbol(
                          section.icon,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        label: Text(section.label),
                      ),
                  ],
                ),
              Expanded(child: _buildPage()),
            ],
          ),
          bottomNavigationBar: isDesktop
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _selectedIndex = index),
                  destinations: [
                    for (final section in _sections)
                      NavigationDestination(
                        icon: MaterialSymbol(section.icon),
                        selectedIcon: MaterialSymbol(
                          section.icon,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        label: section.label,
                      ),
                  ],
                ),
          floatingActionButton: _selectedIndex < 2
              ? FloatingActionButton.extended(
                  onPressed: _createMovement,
                  tooltip: 'Agregar movimiento',
                  backgroundColor: const Color(0xFF075B43),
                  foregroundColor: Colors.white,
                  icon: const MaterialSymbol('add', color: Colors.white),
                  label: const Text('Nuevo movimiento'),
                )
              : null,
        );
      },
    );
  }

  Widget _buildPage() {
    return FutureBuilder<List<MoneyMovement>>(
      future: _movements,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InlineError(message: 'No se pudieron leer los movimientos.');
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final movements = snapshot.data!;
        return switch (_selectedIndex) {
          0 => _DashboardPage(
            movements: movements,
            onAddMovement: _createMovement,
          ),
          1 => _MovementsPage(
            movements: movements,
            onExportCsv: (rows) => _exportMovements(rows, asCsv: true),
            onExportJson: (rows) => _exportMovements(rows, asCsv: false),
          ),
          2 => _ReportsPage(movements: movements),
          _ => _SettingsPage(
            onOpenOwner: () => _openWhatsApp(WhatsAppContacts.owner),
            onOpenCoOwner: () => _openWhatsApp(WhatsAppContacts.coOwner),
            androidAvailable: Platform.isAndroid,
            enabledBankPackages: _enabledBankPackages,
            hasNotificationAccess: _hasNotificationAccess,
            configureBankDetection: _configureBankDetection,
            openNotificationSettings: _openNotificationSettings,
            reviewBankObservations: _reviewBankObservations,
          ),
        };
      },
    );
  }

  Future<void> _openWhatsApp(WhatsAppContact contact) async {
    final opened = await WhatsAppContacts.open(contact);
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No se pudo abrir WhatsApp en este dispositivo.'),
      ),
    );
  }

  Future<void> _reviewBankObservations() async {
    final observations = await (await _observations).listPending();
    if (!mounted) return;
    if (observations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay avisos pendientes de revisión.')),
      );
      return;
    }
    for (final observation in observations) {
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const MaterialSymbol('notification_important'),
          title: Text('Aviso de ${observation.source}'),
          content: Text(
            '${observation.kind == null
                ? 'Tipo sin identificar'
                : observation.kind == MovementKind.income
                ? 'Posible ingreso'
                : 'Posible gasto'} · '
            '${observation.amountMinor == null || observation.currency == null ? 'importe por revisar' : formatMinorAmount(observation.amountMinor!, observation.currency!)}\n'
            '${observation.counterparty == null ? '' : 'Contraparte: ${observation.counterparty}\n'}'
            '${observation.reference == null ? '' : 'Referencia: ${observation.reference}\n'}'
            '${observation.reviewReason == null ? '' : 'Pendiente: ${observation.reviewReason}\n'}\n'
            'Dato extraído de la notificación. Verifícalo con la app o el extracto bancario antes de confirmar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Ignorar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Completar y registrar'),
            ),
          ],
        ),
      );
      if (accepted == null) return;
      if (!mounted) return;
      if (accepted) {
        final movement = await showDialog<MoneyMovement>(
          context: context,
          builder: (dialogContext) => _MovementDialog(
            repository: widget.repository,
            initialId: observation.id,
            initialKind: observation.kind,
            initialAmountMinor: observation.amountMinor,
            initialCategory: 'Transferencia detectada · ${observation.source}',
            initialNote: 'Revisado por el usuario; el aviso no es confirmación bancaria.',
            initialCreatedAt: observation.observedAt,
            origin: MovementOrigin.notification,
            verification: MovementVerification.userReviewed,
            sourceName: observation.source,
            counterparty: observation.counterparty,
            reference: observation.reference,
            method: observation.method,
            reportedStatus: observation.reportedStatus,
          ),
        );
        if (movement == null) continue;
        final saved = await widget.repository.addMovement(movement);
        if (saved) {
          await (await _observations).markReviewed(
            observation.id,
            accepted: true,
          );
        }
      } else {
        await (await _observations).markReviewed(
          observation.id,
          accepted: false,
        );
      }
    }
    if (mounted) _reload();
  }
}

class _SectionData {
  const _SectionData(this.label, this.icon);

  final String label;
  final String icon;
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({required this.movements, required this.onAddMovement});

  final List<MoneyMovement> movements;
  final VoidCallback onAddMovement;

  @override
  Widget build(BuildContext context) {
    final totals = MovementTotals.fromMovements(movements);
    final income = totals.amount('COP', MovementKind.income);
    final expense = totals.amount('COP', MovementKind.expense);
    final balance = income - expense;
    final device = _deviceName(Theme.of(context).platform);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        Text(
          'Tus finanzas, bajo tu control.',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF18201C),
          ),
        ),
        const SizedBox(height: 6),
        Text('$device · Datos guardados en este dispositivo'),
        const SizedBox(height: 20),
        _BalanceCard(balance: balance, currency: 'COP'),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 650 ? 2 : 1;
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: columns == 1 ? 2.7 : 2.1,
              children: [
                _MetricCard(
                  label: 'Ingresos registrados',
                  amount: income,
                  icon: 'trending_up',
                  color: const Color(0xFF087D58),
                  currency: 'COP',
                ),
                _MetricCard(
                  label: 'Gastos registrados',
                  amount: expense,
                  icon: 'trending_down',
                  color: const Color(0xFFB64D3C),
                  currency: 'COP',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Movimientos recientes',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: onAddMovement,
              icon: const MaterialSymbol('add'),
              label: const Text('Agregar'),
            ),
          ],
        ),
        if (movements.isEmpty)
          const _EmptyState(
            icon: 'receipt_long',
            title: 'Todavía no hay movimientos',
            message: 'Agrega un ingreso o un gasto para empezar tu historial.',
          )
        else
          ...movements
              .take(5)
              .map((movement) => _MovementTile(movement: movement)),
        const SizedBox(height: 18),
        const _LocalOnlyNotice(),
        if (totals.currencies.any((currency) => currency != 'COP')) ...[
          const SizedBox(height: 12),
          const Text('Otros saldos están disponibles por moneda en Reportes.'),
        ],
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.currency});

  final int balance;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF075B43), Color(0xFF103C31)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Balance registrado',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            formatMinorAmount(balance, currency),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              MaterialSymbol('cloud_off', color: Color(0xFFF0C66E), size: 18),
              SizedBox(width: 8),
              Text(
                'Solo en este dispositivo',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    this.currency = 'COP',
  });

  final String label;
  final int amount;
  final String icon;
  final Color color;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: MaterialSymbol(icon, color: color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    formatMinorAmount(amount, currency),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementsPage extends StatefulWidget {
  const _MovementsPage({
    required this.movements,
    required this.onExportCsv,
    required this.onExportJson,
  });

  final List<MoneyMovement> movements;
  final Future<void> Function(List<MoneyMovement>) onExportCsv;
  final Future<void> Function(List<MoneyMovement>) onExportJson;

  @override
  State<_MovementsPage> createState() => _MovementsPageState();
}

class _MovementsPageState extends State<_MovementsPage> {
  final _search = TextEditingController();
  MovementKind? _kind;
  String? _currency;
  String? _sourceName;
  MovementOrigin? _origin;
  DateTimeRange? _dateRange;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _chooseDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  @override
  Widget build(BuildContext context) {
    final movements = filterMovements(
      widget.movements,
      text: _search.text,
      kind: _kind,
      currency: _currency,
      sourceName: _sourceName,
      origin: _origin,
      from: _dateRange?.start,
      to: _dateRange?.end,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
      children: [
        Text(
          'Movimientos',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          '${movements.length} de ${widget.movements.length} registros locales',
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Buscar categoría o nota',
            prefixIcon: MaterialSymbol('search'),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<MovementKind?>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todos')),
                  DropdownMenuItem(
                    value: MovementKind.income,
                    child: Text('Ingreso'),
                  ),
                  DropdownMenuItem(
                    value: MovementKind.expense,
                    child: Text('Gasto'),
                  ),
                ],
                onChanged: (value) => setState(() => _kind = value),
              ),
            ),
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String?>(
                initialValue: _currency,
                decoration: const InputDecoration(labelText: 'Moneda'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todas'),
                  ),
                  for (final code in currencyNames.keys)
                    DropdownMenuItem<String?>(value: code, child: Text(code)),
                ],
                onChanged: (value) => setState(() => _currency = value),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String?>(
                initialValue: _sourceName,
                decoration: const InputDecoration(labelText: 'Entidad'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todas'),
                  ),
                  for (final source in bankNotificationPackages.values.toSet())
                    DropdownMenuItem<String?>(
                      value: source,
                      child: Text(source),
                    ),
                ],
                onChanged: (value) => setState(() => _sourceName = value),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<MovementOrigin?>(
                initialValue: _origin,
                decoration: const InputDecoration(labelText: 'Origen'),
                items: const [
                  DropdownMenuItem<MovementOrigin?>(
                    value: null,
                    child: Text('Todos los orígenes'),
                  ),
                  DropdownMenuItem(
                    value: MovementOrigin.notification,
                    child: Text('Notificación'),
                  ),
                  DropdownMenuItem(
                    value: MovementOrigin.manual,
                    child: Text('Manual'),
                  ),
                  DropdownMenuItem(
                    value: MovementOrigin.imported,
                    child: Text('Importado'),
                  ),
                  DropdownMenuItem(
                    value: MovementOrigin.officialIntegration,
                    child: Text('Integración oficial'),
                  ),
                ],
                onChanged: (value) => setState(() => _origin = value),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _chooseDateRange,
              icon: const MaterialSymbol('calendar_month'),
              label: Text(
                _dateRange == null
                    ? 'Fechas'
                    : '${DateFormat('dd/MM').format(_dateRange!.start)}–${DateFormat('dd/MM').format(_dateRange!.end)}',
              ),
            ),
            if (_dateRange != null || _sourceName != null || _origin != null)
              IconButton(
                tooltip: 'Quitar filtros adicionales',
                onPressed: () => setState(() {
                  _dateRange = null;
                  _sourceName = null;
                  _origin = null;
                }),
                icon: const MaterialSymbol('close'),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => widget.onExportCsv(movements),
              icon: const MaterialSymbol('table_view'),
              label: const Text('Exportar CSV'),
            ),
            OutlinedButton.icon(
              onPressed: () => widget.onExportJson(movements),
              icon: const MaterialSymbol('data_object'),
              label: const Text('Exportar JSON'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (movements.isEmpty)
          const _EmptyState(
            icon: 'receipt_long',
            title: 'Tu historial está vacío',
            message: 'Los registros que agregues aparecerán aquí.',
          )
        else
          ...movements.map((movement) => _MovementTile(movement: movement)),
        const SizedBox(height: 18),
        const _LocalOnlyNotice(),
      ],
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement});

  final MoneyMovement movement;

  @override
  Widget build(BuildContext context) {
    final isIncome = movement.kind == MovementKind.income;
    final originLabel = switch (movement.origin) {
      MovementOrigin.manual => 'Registro manual',
      MovementOrigin.notification =>
        'Detectado por ${movement.sourceName ?? 'notificación'}',
      MovementOrigin.imported => 'Importado desde archivo',
      MovementOrigin.officialIntegration =>
        'Integración oficial · ${movement.sourceName ?? 'entidad'}',
    };
    final verificationLabel =
        movement.verification == MovementVerification.unverified
        ? ' · pendiente de verificar en el banco'
        : movement.verification == MovementVerification.userReviewed
        ? ' · revisado por el usuario, no confirmado por el banco'
        : '';
    final details = <String>[
      DateFormat('dd/MM/yyyy · HH:mm').format(movement.createdAt.toLocal()),
      originLabel + verificationLabel,
      if (movement.counterparty != null)
        'Contraparte: ${movement.counterparty}',
      if (movement.reference != null) 'Ref. ${movement.reference}',
      'Guardado local, sin sincronización en nube',
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isIncome
              ? const Color(0xFFE7F3EC)
              : const Color(0xFFF8EAE7),
          child: MaterialSymbol(
            isIncome ? 'trending_up' : 'payments',
            color: isIncome ? const Color(0xFF087D58) : const Color(0xFFB64D3C),
            size: 21,
          ),
        ),
        title: Text(
          movement.category,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(details.join(' · ')),
        isThreeLine: false,
        trailing: Text(
          '${isIncome ? '+' : '−'}${formatMinorAmount(movement.amountMinor, movement.currency)}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: isIncome ? const Color(0xFF087D58) : const Color(0xFFB64D3C),
          ),
        ),
      ),
    );
  }
}

class _ReportsPage extends StatelessWidget {
  const _ReportsPage({required this.movements});

  final List<MoneyMovement> movements;

  @override
  Widget build(BuildContext context) {
    final totals = MovementTotals.fromMovements(movements);
    final currencies = totals.currencies.toList()..sort();
    if (!currencies.contains('COP')) currencies.insert(0, 'COP');
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Resumen de registros',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text('Cálculos locales a partir de tus movimientos guardados.'),
        const SizedBox(height: 18),
        for (final currency in currencies) ...[
          const SizedBox(height: 12),
          Text(currency, style: Theme.of(context).textTheme.titleMedium),
          _MetricCard(
            label: 'Ingresos',
            amount: totals.amount(currency, MovementKind.income),
            icon: 'trending_up',
            color: const Color(0xFF087D58),
            currency: currency,
          ),
          _MetricCard(
            label: 'Gastos',
            amount: totals.amount(currency, MovementKind.expense),
            icon: 'trending_down',
            color: const Color(0xFFB64D3C),
            currency: currency,
          ),
          _MetricCard(
            label: 'Diferencia',
            amount: totals.balance(currency),
            icon: 'pie_chart',
            color: const Color(0xFF876421),
            currency: currency,
          ),
        ],
      ],
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.onOpenOwner,
    required this.onOpenCoOwner,
    required this.androidAvailable,
    required this.enabledBankPackages,
    required this.hasNotificationAccess,
    required this.configureBankDetection,
    required this.openNotificationSettings,
    required this.reviewBankObservations,
  });

  final VoidCallback onOpenOwner;
  final VoidCallback onOpenCoOwner;
  final bool androidAvailable;
  final Set<String> enabledBankPackages;
  final bool hasNotificationAccess;
  final VoidCallback configureBankDetection;
  final VoidCallback openNotificationSettings;
  final VoidCallback reviewBankObservations;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Configuración',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        const Card(
          child: ListTile(
            leading: MaterialSymbol('account_circle'),
            title: Text('Versión 1.2.0'),
            subtitle: Text('BRUGES FINANZAS 360'),
          ),
        ),
        const _LocalOnlyNotice(),
        if (androidAvailable) ...[
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const MaterialSymbol('notifications_active'),
                  title: Text(
                    enabledBankPackages.isEmpty
                        ? 'Detección externa desactivada'
                        : 'Detección externa · ${enabledBankPackages.length} entidad(es)',
                  ),
                  subtitle: Text(
                    '${hasNotificationAccess ? 'Acceso de Android concedido' : 'Falta permiso de notificaciones'} · '
                    '${enabledBankPackages.isEmpty ? 'Sin entidades seleccionadas' : enabledBankPackages.map((package) => bankNotificationPackages[package]).join(', ')}',
                  ),
                  onTap: configureBankDetection,
                  trailing: const MaterialSymbol('tune'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const MaterialSymbol('settings_applications'),
                  title: const Text('Cambiar permiso de Android'),
                  subtitle: const Text(
                    'Concede o revoca el acceso desde los ajustes del sistema.',
                  ),
                  onTap: openNotificationSettings,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const MaterialSymbol('fact_check'),
                  title: const Text('Revisar avisos capturados'),
                  subtitle: const Text(
                    'Completa los avisos ambiguos o con datos incompletos.',
                  ),
                  onTap: reviewBankObservations,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const MaterialSymbol('support_agent'),
                title: const Text('Contactar soporte'),
                subtitle: const Text('WhatsApp · 305 233 0643'),
                trailing: const MaterialSymbol('open_in_new'),
                onTap: onOpenOwner,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const MaterialSymbol('support_agent'),
                title: const Text('Contactar copropietario'),
                subtitle: const Text('WhatsApp · 311 578 8917'),
                trailing: const MaterialSymbol('open_in_new'),
                onTap: onOpenCoOwner,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocalOnlyNotice extends StatelessWidget {
  const _LocalOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF8E9),
      child: const Padding(
        padding: EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MaterialSymbol('cloud_off', color: Color(0xFF876421)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Los movimientos se conservan en este dispositivo. La sincronización en internet aún no está conectada.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2D4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MaterialSymbol('cloud_off', size: 16, color: Color(0xFF876421)),
          SizedBox(width: 5),
          Text(
            'Solo local',
            style: TextStyle(fontSize: 11, color: Color(0xFF604715)),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final String icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          children: [
            MaterialSymbol(icon, size: 34, color: const Color(0xFF69756D)),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog({
    required this.repository,
    this.initialId,
    this.initialKind,
    this.initialAmountMinor,
    this.initialCategory = '',
    this.initialNote = '',
    this.initialCreatedAt,
    this.origin = MovementOrigin.manual,
    this.verification = MovementVerification.userProvided,
    this.sourceName,
    this.counterparty,
    this.reference,
    this.method,
    this.reportedStatus,
  });

  final MovementRepository repository;
  final String? initialId;
  final MovementKind? initialKind;
  final int? initialAmountMinor;
  final String initialCategory;
  final String initialNote;
  final DateTime? initialCreatedAt;
  final MovementOrigin origin;
  final MovementVerification verification;
  final String? sourceName;
  final String? counterparty;
  final String? reference;
  final String? method;
  final String? reportedStatus;

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _category;
  late final TextEditingController _note;
  late MovementKind _kind;
  String _currency = 'COP';

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind ?? MovementKind.expense;
    final amountMinor = widget.initialAmountMinor;
    _amount = TextEditingController(
      text: amountMinor == null
          ? ''
          : currencyDecimalDigits(_currency) == 0
          ? amountMinor.toString()
          : (amountMinor / 100).toStringAsFixed(2),
    );
    _category = TextEditingController(text: widget.initialCategory);
    _note = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _amount.dispose();
    _category.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final amount = parseMajorAmount(_amount.text, _currency);
    if (amount == null) return;
    Navigator.of(context).pop(
      MoneyMovement(
        id: widget.initialId ?? widget.repository.createId(),
        kind: _kind,
        amountMinor: amount,
        currency: _currency,
        category: _category.text.trim(),
        note: _note.text.trim(),
        createdAt: widget.initialCreatedAt ?? DateTime.now().toUtc(),
        origin: widget.origin,
        verification: widget.verification,
        sourceName: widget.sourceName,
        counterparty: widget.counterparty,
        reference: widget.reference,
        method: widget.method,
        reportedStatus: widget.reportedStatus,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.origin == MovementOrigin.notification
            ? 'Completar movimiento detectado'
            : 'Nuevo movimiento',
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<MovementKind>(
                segments: const [
                  ButtonSegment(
                    value: MovementKind.expense,
                    label: Text('Gasto'),
                    icon: MaterialSymbol('trending_down'),
                  ),
                  ButtonSegment(
                    value: MovementKind.income,
                    label: Text('Ingreso'),
                    icon: MaterialSymbol('trending_up'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (selection) =>
                    setState(() => _kind = selection.first),
              ),
              const SizedBox(height: 14),
              TextFormField(
                key: const Key('movement-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Valor en moneda principal',
                  prefixText: '$_currency ',
                ),
                validator: (value) {
                  final parsed = parseMajorAmount(value ?? '', _currency);
                  return parsed == null
                      ? 'Escribe un valor válido para $_currency.'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('movement-currency'),
                initialValue: _currency,
                decoration: const InputDecoration(labelText: 'Moneda'),
                items: [
                  for (final code in currencyNames.keys)
                    DropdownMenuItem(
                      value: code,
                      child: SizedBox(
                        width: 170,
                        child: Text(
                          '$code · ${currencyNames[code]}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _currency = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('movement-category'),
                controller: _category,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Categoría'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Escribe una categoría.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nota (opcional)'),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _save, child: const Text('Guardar movimiento')),
      ],
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: SvgPicture.asset(
                'assets/branding/bruges_finanzas_360.svg',
              ),
            ),
            SizedBox(height: 20),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _StorageError extends StatelessWidget {
  const _StorageError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MaterialSymbol('error', size: 42, color: Color(0xFFB64D3C)),
              const SizedBox(height: 12),
              const Text('No se pudo abrir el almacenamiento local.'),
              const SizedBox(height: 6),
              SelectableText('$error'),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(child: Text(message));
}

String _deviceName(TargetPlatform platform) => switch (platform) {
  TargetPlatform.android => 'Android',
  TargetPlatform.windows => 'Windows',
  TargetPlatform.iOS => 'iPhone / iPad',
  TargetPlatform.macOS => 'Mac',
  TargetPlatform.linux => 'Linux',
  TargetPlatform.fuchsia => 'Fuchsia',
};
