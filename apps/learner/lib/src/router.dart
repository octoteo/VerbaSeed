import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/curriculum/curriculum_page.dart';
import 'features/explore/explore_page.dart';
import 'features/home/home_page.dart';
import 'features/import/course_draft_review_page.dart';
import 'features/import/ocr_import_page.dart';
import 'features/practice/sentence_typing_page.dart';
import 'features/profiles/profiles_page.dart';
import 'features/settings/backup_restore_page.dart';
import 'features/settings/github_course_updates_page.dart';
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
                  builder: (context, state) => const OcrImportPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (context, state) => const SettingsPage(),
                  routes: [
                    GoRoute(
                      path: 'github-courses',
                      builder: (context, state) =>
                          const GitHubCourseUpdatesPage(),
                    ),
                    GoRoute(
                      path: 'backup-restore',
                      builder: (context, state) => const BackupRestorePage(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/profiles',
          builder: (context, state) => const ProfilesPage(),
        ),
        GoRoute(
          path: '/practice/typing',
          builder: (context, state) => const SentenceTypingPage(),
        ),
        GoRoute(
          path: '/import/draft/:jobId',
          builder: (context, state) => CourseDraftReviewPage(
            jobId: state.pathParameters['jobId']!,
          ),
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: Center(child: Text('Page not found: ${state.uri}')),
      ),
    );
