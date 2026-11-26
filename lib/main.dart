import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/catalog.dart';
import 'features/custom_pose.dart';
import 'features/camera.dart';
import 'features/notebook.dart';
import 'features/pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Pose.load();
  final db = await openNotebook();
  for (final row in await db.query('custom_poses')) {
    Pose.registerCustom(row);
  }
  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const PicPic(),
    ),
  );
}

class PicPic extends StatefulWidget {
  const PicPic({
    super.key,
    this.demo = const bool.fromEnvironment('PICPIC_DEMO'),
  });
  final bool demo;
  @override
  State<PicPic> createState() => _PicPicState();
}

class _PicPicState extends State<PicPic> {
  late final router = GoRouter(
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Scaffold(
          body: shell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (i) =>
                shell.goBranch(i, initialLocation: i == shell.currentIndex),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: '首页',
              ),
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                label: '姿势',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                label: '创作',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                label: '我的',
              ),
            ],
          ),
        ),
        branches: [
          for (final (path, page) in <(String, Widget)>[
            ('/', const HomePage()),
            ('/poses', const LibraryPage()),
            ('/create', const CreatePage()),
            ('/me', const ProfilePage()),
          ])
            StatefulShellBranch(
              routes: [GoRoute(path: path, builder: (_, _) => page)],
            ),
        ],
      ),
      GoRoute(
        path: '/browse',
        builder: (_, s) => LibraryPage(
          initial: s.uri.queryParameters['filter'] ?? '全部',
          standalone: true,
        ),
      ),
      GoRoute(
        path: '/pose/:id',
        builder: (_, s) => PoseDetail(Pose.find(s.pathParameters['id']!)!),
      ),
      GoRoute(
        path: '/camera/:id',
        builder: (_, s) => ShootPage(
          pose: Pose.find(s.pathParameters['id']!)!,
          demo: widget.demo,
          plan: int.tryParse(s.uri.queryParameters['plan'] ?? ''),
        ),
      ),
      GoRoute(path: '/plans', builder: (_, _) => const PlansPage()),
      GoRoute(
        path: '/plans/new',
        builder: (_, s) => NewPlanPage(initial: s.uri.queryParameters['pose']),
      ),
      GoRoute(
        path: '/plans/:id',
        builder: (_, s) => PlanDetail(int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(path: '/custom', builder: (_, _) => const CustomPosePage()),
      GoRoute(path: '/photos', builder: (_, _) => const PhotoPage()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
    ],
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'PicPic',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: const ColorScheme.dark(
        surface: Color(0xff171717),
        primary: Color(0xffeee9df),
        onPrimary: Color(0xff282622),
      ),
      scaffoldBackgroundColor: const Color(0xff141414),
      useMaterial3: true,
      navigationBarTheme: const NavigationBarThemeData(
        height: 66,
        backgroundColor: Color(0xff191919),
        indicatorColor: Color(0xff42403c),
      ),
    ),
    routerConfig: router,
  );
}

class ShootPage extends ConsumerStatefulWidget {
  const ShootPage({
    super.key,
    required this.pose,
    required this.demo,
    this.plan,
  });
  final Pose pose;
  final bool demo;
  final int? plan;
  @override
  ConsumerState<ShootPage> createState() => _ShootPageState();
}

class _ShootPageState extends ConsumerState<ShootPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(notebookProvider.notifier).use(widget.pose.id),
    );
  }

  @override
  Widget build(BuildContext context) => Viewfinder(
    demo: widget.demo,
    initial: widget.pose,
    onUse: (p) => ref.read(notebookProvider.notifier).use(p.id),
    onSaved: (p, path) =>
        ref.read(notebookProvider.notifier).captured(p.id, path, widget.plan),
  );
}
