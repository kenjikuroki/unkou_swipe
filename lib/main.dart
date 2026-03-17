import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

import 'package:appinio_swiper/appinio_swiper.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'dart:convert';
import 'widgets/ad_banner.dart';
import 'utils/ad_manager.dart';
import 'utils/purchase_manager.dart';
import 'widgets/premium_unlock_card.dart';
import 'widgets/special_offer_dialog.dart';
import 'utils/prefs_helper.dart';
import 'utils/migration_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

import 'widgets/mode_toggle.dart';
import 'widgets/premium_upgrade_dialog.dart';
import 'widgets/category_review_modal.dart';
import 'widgets/tutorial_overlay.dart';
import 'models/app_data.dart';
import 'utils/api_service.dart';
import 'utils/responsive_helper.dart';
import 'package:in_app_review/in_app_review.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Initialize Purchase Manager
  await PurchaseManager.instance.initialize();
  
  runApp(const MyApp());
}

// -----------------------------------------------------------------------------
// 1. Data Models & Helpers
// -----------------------------------------------------------------------------

// Data Models & Helpers are now in lib/models/app_data.dart
// QuizData is replaced by ApiService and dynamic AppData in _MyHomePageState


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '浄化槽管理士対策',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja', ''),
      ],
      locale: const Locale('ja', ''),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A),
          primary: const Color(0xFF1E293B),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: ResponsiveHelper.respFontSize(context, 20),
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

// -----------------------------------------------------------------------------
// 2. Home Page
// -----------------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _weaknessCount = 0;
  bool _isLoading = true;
  bool _isSequentialMode = false;
  Map<String, int> _categoryWeaknessCounts = {};
  AppData? _appData;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }
  
  Future<void> _initializeApp() async {
    // 1. Wait for 1 second
    await Future.delayed(const Duration(seconds: 1));

    // Data Migration from V1 (local) to V2 (GAS)
    await MigrationHelper.performMigration();

    // 2. Request ATT
    final status = await AppTrackingTransparency.requestTrackingAuthorization();
    debugPrint("ATT Status: $status");

    // 3. Initialize Ads
    await MobileAds.instance.initialize();
    
    // 4. Preload Ads
    AdManager.instance.preloadAd('home');

    // Load dynamic data from GAS
    final apiService = ApiService();
    _appData = await apiService.loadAppData('unkou');


    if (_appData != null) {
      AdManager.instance.setAdUnitIds(
        bannerId: _appData!.config.adBannerId,
        interstitialId: _appData!.config.adInterstitialId,
      );
      // PurchaseManager.instance.setProductId(_appData!.config.premiumProductId);
    }

    await _loadUserData();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadUserData() async {
    final weakList = await PrefsHelper.getWeakQuestions();
    if (_appData == null) return;
    
    // Calculate counts for each category
    final counts = <String, int>{};
    
    for (var entry in _appData!.questions.entries) {
      final categoryKey = entry.key;
      final questions = entry.value;
      final categoryQuestionTexts = questions.map((q) => q.question).toSet();
      
      int count = 0;
      for (var weakText in weakList) {
        if (categoryQuestionTexts.contains(weakText)) {
          count++;
        }
      }
      counts[categoryKey] = count;
    }

    if (mounted) {
      setState(() {
        _weaknessCount = weakList.length;
        _categoryWeaknessCounts = counts;
      });
    }
  }

  void _startQuiz(BuildContext context, List<Quiz> quizList, String categoryKey) async {
    List<Quiz> questionsToUse = List<Quiz>.from(quizList);
    
    if (!_isSequentialMode) {
      // Shuffle Mode (10 questions)
      questionsToUse.shuffle();
      if (questionsToUse.length > 10) {
        questionsToUse = questionsToUse.take(10).toList();
      }
    } else {
      // Sequential Mode (All questions, no shuffle)
      // They are already in order from the API data
    }
    
    AdManager.instance.preloadAd('result');
    AdManager.instance.preloadAd('quiz');
    AdManager.instance.preloadInterstitial();
    
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuizPage(
          quizzes: questionsToUse,
          categoryKey: categoryKey,
          totalQuestions: questionsToUse.length,
        ),
      ),
    );
    if (!mounted) return;
    _loadUserData();
  }

  void _showPremiumDialog() {
    showDialog(
      context: context,
      builder: (context) => const PremiumUpgradeDialog(),
    );
  }

  void _startWeaknessReview(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => CategoryReviewModal(
        counts: _categoryWeaknessCounts,
        categoryOrder: _appData!.categoryOrder,
        onCategorySelected: (categoryKey) => _startWeaknessReviewByCategory(context, categoryKey),
      ),
    );
  }

  void _startWeaknessReviewByCategory(BuildContext context, String categoryKey) async {
    final weakTexts = await PrefsHelper.getWeakQuestions();
    if (!mounted || _appData == null) return;
    if (weakTexts.isEmpty) return;

    final categoryQuizzes = _appData!.questions[categoryKey] ?? [];
    if (categoryQuizzes.isEmpty) return;

    final categoryQuestionsSet = categoryQuizzes.map((q) => q.question).toSet();
    final weakQuizzes = _getQuizzesFromTexts(weakTexts)
        .where((q) => categoryQuestionsSet.contains(q.question))
        .toList();
    
    if (weakQuizzes.isEmpty) return;

    AdManager.instance.preloadAd('result');
    AdManager.instance.preloadAd('quiz');
    AdManager.instance.preloadInterstitial();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => QuizPage(
          quizzes: weakQuizzes,
          isWeaknessReview: true,
          totalQuestions: weakQuizzes.length,
        ),
      ),
    );
    if (!mounted) return;
    _loadUserData();
  }

  List<Quiz> _getQuizzesFromTexts(List<String> texts) {
    if (_appData == null) return [];
    
    final allQuizzes = _appData!.questions.values.expand((element) => element).toList();
    return allQuizzes.where((q) => texts.contains(q.question)).toList();
  }

  void _startQuizByCategory(BuildContext context, String categoryKey) {
    if (_appData == null) return;
    
    final quizzes = _appData!.questions[categoryKey] ?? [];
    final highScoreKey = 'highscore_$categoryKey';
    
    if (quizzes.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('問題データがまだありません')),
       );
       return;
    }
    _startQuiz(context, quizzes, highScoreKey);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_appData?.config.appTitle ?? l10n.appTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  // Subtitle removed as per user request
                  const SizedBox(height: 8),
                  
                  // Mode Toggle
                  Center(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: PurchaseManager.instance.isPremium,
                      builder: (context, isPremium, child) {
                        return ModeToggle(
                          isSequential: _isSequentialMode,
                          isPremium: isPremium,
                          onModeChanged: (val) {
                            setState(() {
                              _isSequentialMode = val;
                            });
                          },
                          onLockedTap: _showPremiumDialog,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Dynamic Part Buttons
                  if (_appData != null)
                    ..._appData!.categoryOrder.asMap().entries.map((entry) {
                      final index = entry.key;
                      final catName = entry.value;
                      
                      final colors = [
                        Colors.blueAccent,
                        Colors.orange,
                        Colors.redAccent,
                        Colors.green,
                        Colors.purpleAccent,
                        Colors.teal,
                      ];
                      final color = colors[index % colors.length];

                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: double.infinity,
                            maxWidth: ResponsiveHelper.respCardWidth(context) ?? double.infinity,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _MenuButton(
                              title: catName,
                              icon: Icons.menu_book_rounded,
                              iconColor: color,
                              onTap: () => _startQuizByCategory(context, catName),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  if (_appData != null && _appData!.categoryOrder.isNotEmpty)
                    const SizedBox(height: 24),

                  // Weakness Review
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: double.infinity,
                        maxWidth: ResponsiveHelper.respCardWidth(context) ?? double.infinity,
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _weaknessCount > 0 ? () => _startWeaknessReview(context) : null,
                        icon: const Icon(Icons.menu_book_rounded),
                        label: Text(l10n.reviewWeakness(_weaknessCount)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.respPadding(context, 16),
                          ),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: TextStyle(
                            fontSize: ResponsiveHelper.respFontSize(context, 18),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Sister App Promotion
                  ValueListenableBuilder<bool>(
                    valueListenable: PurchaseManager.instance.isPremium,
                    builder: (context, isPremium, child) {
                      if (isPremium) return const SizedBox.shrink();
                      if (_appData?.config.nextAppEnabled == false) return const SizedBox.shrink();
                      
                      return Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: double.infinity,
                            maxWidth: ResponsiveHelper.respCardWidth(context) ?? double.infinity,
                          ),
                          child: Column(
                            children: [
                              _SisterAppPromotion(config: _appData?.config),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: double.infinity,
                        maxWidth: ResponsiveHelper.respCardWidth(context) ?? double.infinity,
                      ),
                      child: const PremiumUnlockCard(),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _MenuButton({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.respPadding(context, 20.0),
              vertical: ResponsiveHelper.respPadding(context, 12.0),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.respPadding(context, 12)),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: ResponsiveHelper.respIconSize(context, 32),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.respPadding(context, 20)),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: ResponsiveHelper.respFontSize(context, 18),
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1E293B),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Colors.blueGrey[300],
                  size: ResponsiveHelper.respIconSize(context, 28),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}




// -----------------------------------------------------------------------------
// 3. Quiz Page
// -----------------------------------------------------------------------------

class QuizPage extends StatefulWidget {
  final List<Quiz> quizzes;
  final String? categoryKey;
  final bool isWeaknessReview;
  final int totalQuestions;

  const QuizPage({
    super.key,
    required this.quizzes,
    this.categoryKey,
    this.isWeaknessReview = false,
    required this.totalQuestions,
  });

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final AppinioSwiperController controller = AppinioSwiperController();
  
  int _score = 0;
  int _currentIndex = 1;
  final List<Quiz> _incorrectQuizzes = [];
  final List<Quiz> _correctQuizzesInReview = [];
  final List<Map<String, dynamic>> _answerHistory = [];
  Color _backgroundColor = const Color(0xFFF1F5F9);
  bool _showTutorial = false;

  @override
  void initState() {
    super.initState();
    _checkTutorial();
  }

  Future<void> _checkTutorial() async {
    final shown = await PrefsHelper.isTutorialShown();
    if (!shown && mounted) {
      setState(() {
        _showTutorial = true;
      });
    }
  }

  void _dismissTutorial() {
    setState(() {
      _showTutorial = false;
    });
    PrefsHelper.markTutorialShown();
  }

  void _handleSwipeEnd(int previousIndex, int targetIndex, SwiperActivity activity) {
    if (activity is Swipe) {
      final quiz = widget.quizzes[previousIndex];
      bool userVal = (activity.direction == AxisDirection.right);
      bool isCorrect = (userVal == quiz.isCorrect);

      _answerHistory.add({
        'quiz': quiz,
        'result': isCorrect,
      });

      setState(() {
        if (isCorrect) {
          _score++;
          _backgroundColor = Colors.green.withValues(alpha: 0.2);
          HapticFeedback.lightImpact();
          
          if (widget.isWeaknessReview) {
            _recordWeakness(quiz.question, true);
          }
        } else {
          _backgroundColor = Colors.red.withValues(alpha: 0.2);
          _incorrectQuizzes.add(quiz);
          HapticFeedback.heavyImpact();
          _recordWeakness(quiz.question, false);
        }
      });

      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() {
            _backgroundColor = const Color(0xFFF1F5F9);
          });
        }
      });

      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 600),
          content: Text(
            isCorrect ? "正解！ ⭕" : "不正解... ❌",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: ResponsiveHelper.respFontSize(context, 18),
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: isCorrect ? Colors.green : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: MediaQuery.of(context).size.height * 0.5,
            left: ResponsiveHelper.respPadding(context, 50),
            right: ResponsiveHelper.respPadding(context, 50),
          ),
        ),
      );

      setState(() {
        if (_currentIndex < widget.totalQuestions) {
          _currentIndex++;
        }
      });

      if (previousIndex == widget.quizzes.length - 1) {
        _finishQuiz();
      }
    }
  }

  Future<void> _finishQuiz() async {
    if (widget.categoryKey != null) {
      await PrefsHelper.saveHighScore(widget.categoryKey!, _score);
    }

    // Increment quiz completion count and check for review prompt
    final completionCount = await PrefsHelper.incrementQuizCompletionCount();
    if (completionCount == 3) {
      final InAppReview inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        inAppReview.requestReview();
      }
    }

    if (_incorrectQuizzes.isNotEmpty) {
      final incorrectTexts = _incorrectQuizzes.map((q) => q.question).toList();
      await PrefsHelper.addWeakQuestions(incorrectTexts);
    }

    if (widget.isWeaknessReview && _correctQuizzesInReview.isNotEmpty) {
      final correctTexts = _correctQuizzesInReview.map((q) => q.question).toList();
      await PrefsHelper.removeWeakQuestions(correctTexts);
    }
    
    if (mounted) {
      final shouldShow = await PrefsHelper.shouldShowInterstitial();
      
      if (shouldShow) {
        AdManager.instance.showInterstitial(
          onComplete: () async {
            if (mounted) {
              // After interstitial, check for special offer
              final showOffer = await PurchaseManager.instance.shouldShowSpecialOffer();
              if (showOffer && mounted) {
                await PurchaseManager.instance.markSpecialOfferAsShown();
                if (!mounted) return;
                await showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const SpecialOfferDialog(),
                );
              }
              if (mounted) {
                _navigateToResult();
              }
            }
          },
        );
      } else {
        _navigateToResult();
      }
    }
  }

  Future<void> _recordWeakness(String question, bool isCorrect) async {
    if (isCorrect) {
      await PrefsHelper.removeWeakQuestions([question]);
    } else {
      await PrefsHelper.addWeakQuestions([question]);
    }
  }

  void _navigateToResult() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ResultPage(
          score: _score,
          total: widget.quizzes.length,
          history: _answerHistory,
          incorrectQuizzes: _incorrectQuizzes,
          originalQuizzes: widget.quizzes,
          categoryKey: widget.categoryKey,
          isWeaknessReview: widget.isWeaknessReview,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
      body: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            color: _backgroundColor,
            child: SafeArea(
              child: Column(
                children: [
                  // Custom Header Row
                  Padding(
                    padding: EdgeInsets.fromLTRB(4, ResponsiveHelper.isTablet(context) ? 24 : 8, 24, 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, color: Colors.black54, size: 40),
                          onPressed: () => Navigator.of(context).pop(),
                          iconSize: 40,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _currentIndex / widget.totalQuestions,
                              minHeight: 8,
                              backgroundColor: Colors.grey[300],
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          "$_currentIndex / ${widget.totalQuestions}",
                          style: TextStyle(
                            fontSize: ResponsiveHelper.respFontSize(context, 14),
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                      child: AppinioSwiper(
                        controller: controller,
                        cardCount: widget.quizzes.length,
                        loop: false,
                        backgroundCardCount: 2,
                        swipeOptions: const SwipeOptions.symmetric(horizontal: true, vertical: false),
                        onSwipeEnd: _handleSwipeEnd,
                        cardBuilder: (context, index) {
                          return _buildCard(widget.quizzes[index]);
                        },
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.only(bottom: 40, top: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            controller.unswipe();
                            setState(() {
                              if (_currentIndex > 1) {
                                _currentIndex--;
                              }
                              if (_answerHistory.isNotEmpty) {
                                final last = _answerHistory.removeLast();
                                final bool wasCorrect = last['result'];
                                final Quiz quiz = last['quiz'];
                                
                                if (wasCorrect) {
                                  _score--;
                                  if (widget.isWeaknessReview) {
                                    _correctQuizzesInReview.remove(quiz);
                                  }
                                } else {
                                  _incorrectQuizzes.remove(quiz);
                                }
                              }
                            });
                          },
                          icon: const Icon(Icons.undo),
                          label: Text(l10n.back),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                            elevation: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Ad Banner for Quiz
                  SafeArea(
                    top: false,
                    child: ValueListenableBuilder<bool>(
                      valueListenable: PurchaseManager.instance.isPremium,
                      builder: (context, isPremium, child) {
                        if (isPremium) return const SizedBox.shrink();
                        return const SizedBox(
                          height: 60,
                          child: AdBanner(adKey: 'quiz', keepAlive: true),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showTutorial)
            Positioned.fill(
              child: TutorialOverlay(onDismiss: _dismissTutorial),
            ),
        ],
      ),
    ),
  );
}

  Widget _buildCard(Quiz quiz) {
    bool hasImage = quiz.imagePath != null;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: double.infinity,
          maxWidth: ResponsiveHelper.respCardWidth(context) ?? double.infinity,
        ),
        child: Container(
      margin: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        children: [
          if (hasImage) 
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity,
                color: Colors.grey[200],
                child: Image.asset(
                  quiz.imagePath!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text("Image not found", style: TextStyle(color: Colors.grey[600])),
                      ],
                    );
                  },
                ),
              ),
            ),

          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Q.",
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: AutoSizeText(
                      quiz.question,
                      style: TextStyle(
                        fontSize: hasImage ? 24 : 32,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.left,
                      minFontSize: 12,
                      stepGranularity: 1,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
           const Padding(
            padding: EdgeInsets.only(left: 40.0, right: 40.0, bottom: 40.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    Icon(Icons.close, color: Colors.redAccent, size: 48),
                    Text("誤り", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                Column(
                  children: [
                    Icon(Icons.circle_outlined, color: Colors.green, size: 48),
                    Text("正しい", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          if (hasImage) const SizedBox(height: 10),
        ],
      ),
     ),
    ),
   );
  }

}

class _SisterAppPromotion extends StatelessWidget {
  final AppConfig? config;
  const _SisterAppPromotion({this.config});

  Future<void> _launchURL(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    String urlString = config?.nextAppUrl ?? '6758681333';
    
    // If urlString is purely numeric, treat it as an Apple App ID
    if (RegExp(r'^\d+$').hasMatch(urlString)) {
      urlString = 'https://apps.apple.com/app/id$urlString';
    }
    
    final Uri url = Uri.parse(urlString);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                 Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.deepOrange[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.lightbulb_rounded, color: Colors.deepOrange, size: 40),
                ),
                const SizedBox(height: 16),
                Text(
                  config?.nextAppText != null ? config!.nextAppText : l10n.sisterAppDialogTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.sisterAppDialogBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n.cancel, style: const TextStyle(color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          if (!await launchUrl(url)) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(l10n.noData)), // Reuse or add more specific
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Text(l10n.open, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      elevation: 4,
      color: Colors.white,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _launchURL(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.respPadding(context, 16.0)),
          child: Row(
            children: [
               Container(
                width: ResponsiveHelper.respSize(context, 60),
                height: ResponsiveHelper.respSize(context, 60),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.lightbulb_rounded,
                  color: Colors.deepOrange,
                  size: ResponsiveHelper.respIconSize(context, 32),
                ),
              ),
              SizedBox(width: ResponsiveHelper.respPadding(context, 16)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.sisterAppPromoTitle,
                      style: TextStyle(
                        fontSize: ResponsiveHelper.respFontSize(context, 12),
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      config?.nextAppText != null ? config!.nextAppText : l10n.sisterAppPromoSubtitle,
                      style: TextStyle(
                        fontSize: ResponsiveHelper.respFontSize(context, 15),
                        fontWeight: FontWeight.bold,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.launch,
                color: Colors.grey,
                size: ResponsiveHelper.respIconSize(context, 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. Result Page
// -----------------------------------------------------------------------------

class ResultPage extends StatelessWidget {
  final int score;
  final int total;
  final List<Map<String, dynamic>> history;
  final List<Quiz> incorrectQuizzes;
  final List<Quiz> originalQuizzes;
  final String? categoryKey;
  final bool isWeaknessReview;

  const ResultPage({
    super.key,
    required this.score,
    required this.total,
    required this.history,
    required this.incorrectQuizzes,
    required this.originalQuizzes,
    this.categoryKey,
    required this.isWeaknessReview,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea( // 1. SafeArea内
        child: Column(
          children: [
            // -----------------------------------------------------------------
            // 1. 上部エリア
            // -----------------------------------------------------------------
            const AdBanner(adKey: 'result'), // 一番上に広告バナー

            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: double.infinity,
                  maxWidth: ResponsiveHelper.respCardWidth(context) ?? double.infinity,
                ),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32), // 角丸32px
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))
                    ],
                  ),
                  child: Column(
                    children: [
                       Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "正解数",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "$score/$total", // 9/10のようなスコア
                            style: TextStyle(
                              fontSize: ResponsiveHelper.respFontSize(context, 48),
                              fontWeight: FontWeight.w900, // 太字
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      
                      if (score == total)
                        const Text(
                          "PERFECT! 🎉",
                          style: TextStyle(fontSize: 20, color: Colors.green, fontWeight: FontWeight.bold),
                        )
                      else
                        Text(
                          score >= 8 ? "合格圏内！素晴らしい！" : "あと少し！復習しよう",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: score >= 8 ? Colors.green : Colors.red,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // -----------------------------------------------------------------
            // 2. 中央エリア（スクロール可能なリスト）
            // -----------------------------------------------------------------
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final item = history[index];
                  final Quiz quiz = item['quiz'];
                  final bool isCorrect = item['result'];

                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: double.infinity,
                        maxWidth: ResponsiveHelper.respCardWidth(context) ?? double.infinity,
                      ),
                      child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16), // 角丸16px
                      side: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                isCorrect ? Icons.check_circle : Icons.cancel,
                                color: isCorrect ? Colors.green : Colors.red,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      quiz.question,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    if (quiz.imagePath != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Row(
                                          children: [
                                            Icon(Icons.image, size: 16, color: Colors.grey[500]),
                                            const SizedBox(width: 4),
                                            Text("画像問題", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.05), // 薄い青灰色
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "💡 ${quiz.explanation}",
                              style: TextStyle(
                                color: Colors.blueGrey[700],
                                fontSize: ResponsiveHelper.respFontSize(context, 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
              ),
            ),
            
            // -----------------------------------------------------------------
            // 3. 下部エリア（固定フッター）
            // -----------------------------------------------------------------
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFFF9F9F9),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: double.infinity,
                    maxWidth: ResponsiveHelper.respCardWidth(context) ?? double.infinity,
                  ),
                  child: Column(
                    children: [
                  Row(
                    children: [
                      // 左ボタン: 「ミスを確認」 (全問正解時は非表示)
                      if (incorrectQuizzes.isNotEmpty) ...[
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (context) => QuizPage(
                                      quizzes: incorrectQuizzes,
                                      isWeaknessReview: true,
                                      totalQuestions: incorrectQuizzes.length,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.menu_book_rounded),
                              label: const Text("ミスを確認"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],

                      // 右ボタン: 「リトライ」 or 「ホームに戻る」
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () {
                              if (this.isWeaknessReview) {
                                Navigator.of(context).popUntil((route) => route.isFirst);
                                return;
                              }

                              final shuffledAgain = List<Quiz>.from(this.originalQuizzes)..shuffle();
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (context) => QuizPage(
                                    quizzes: shuffledAgain,
                                    categoryKey: this.categoryKey,
                                    totalQuestions: shuffledAgain.length,
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.blueAccent,
                              elevation: 0,
                              side: const BorderSide(color: Colors.blueAccent, width: 2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            child: Text(isWeaknessReview ? "ホームに戻る" : "リトライ"),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  
                  // ホームに戻るリンク
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: const Text("ホームに戻る", style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
             ),
            ),
           ),
          ],
        ),
      ),
    ),
  );
}
}
