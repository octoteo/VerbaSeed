import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'features/curriculum/curriculum_page.dart';
import 'features/explore/explore_page.dart';
import 'features/home/home_page.dart';
import 'features/import/import_page.dart';
import 'features/settings/settings_page.dart';
import 'shell/app_shell.dart';

GoRouter createRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(path: '/', builder: (context, state) => const HomePage()),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/explore',
                  builder: (context, state) => const ExplorePage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/curriculum',
                  builder: (context, state) => const CurriculumPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/import',
                  builder: (context, state) => const ImportPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (context, state) => const SettingsPage(),
                ),
              ],
            ),
          ],
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: Center(child: Text('Page not found: ${state.uri}')),
      ),
    );
