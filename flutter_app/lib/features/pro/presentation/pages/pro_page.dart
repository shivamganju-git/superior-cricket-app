import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../core/providers/auth_provider.dart';

class ProPage extends ConsumerStatefulWidget {
  const ProPage({super.key});

  @override
  ConsumerState<ProPage> createState() => _ProPageState();
}

class _ProPageState extends ConsumerState<ProPage> {
  late Razorpay _razorpay;
  bool _isLoading = false;
  String _selectedPlan = 'pro'; // Default selection

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    try {
      final user = ref.read(authStateProvider).user;
      if (user != null) {
        // Update subscription in backend
        await ref.read(profileRepositoryProvider).updateSubscriptionPlan(user.id, 'pro');
        
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
               content: Text('PRO Membership Activated! Payment ID: ${response.paymentId}'),
               backgroundColor: Colors.green,
             ),
           );
           // Refresh auth state to reflect new subscription
           ref.invalidate(authStateProvider);
        }
      }
    } catch (e) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Activation failed: $e'), backgroundColor: Colors.red),
         );
       }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment Failed: ${response.message}'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _handlePayment() async {
    setState(() {
      _isLoading = true;
    });

    final user = ref.read(authStateProvider).user;
    final email = user?.email ?? 'cricketer@pitchpoint.com';

    var options = {
      'key': 'rzp_test_1DP5mmOlF5G5ag', // Test Key
      'amount': 99900, // ₹999 in paise
      'name': 'PitchPoint Pro',
      'description': 'Annual Pro Membership Subscription',
      'retry': {'enabled': true, 'max_count': 1},
      'send_sms_hash': true,
      'prefill': {
        'contact': '', 
        'email': email
      },
      'theme': {
        'color': '#007AFF'
      }
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isPro = authState.user?.subscriptionPlan == 'pro';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27), // Dark background
      appBar: AppBar(
        title: const Text(
          'MEMBERSHIP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
          ),
        )
          .animate()
          .fadeIn(duration: 400.ms)
          .slideY(begin: -0.2, end: 0),
        centerTitle: true,
        backgroundColor: const Color(0xFF0A0E27),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => GoRouter.of(context).go('/'),
        )
          .animate()
          .fadeIn(duration: 400.ms, delay: 100.ms)
          .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1)),
      ),
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          children: [
            // Hero Section
            _buildEnhancedHero(isPro),
            
            _buildInteractivePlans(isPro),
            
            const SizedBox(height: 32),
            
            _buildSectionHeader('EXCLUSIVE BENEFITS')
              .animate()
              .fadeIn(duration: 500.ms, delay: 600.ms)
              .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),
            
            _buildEnhancedBenefitsList(),
            
            const SizedBox(height: 60), // Balanced padding for bottom visibility
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancedHero(bool isPro) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1F3A),
            Color(0xFF0F1429),
            Color(0xFF0A0E27),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 40,
            spreadRadius: 8,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 40),
      child: Column(
        children: [
          _buildBranding()
            .animate()
            .fadeIn(duration: 500.ms, delay: 100.ms)
            .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1), curve: Curves.elasticOut),
          const SizedBox(height: 32),
          _buildHeroText()
            .animate()
            .fadeIn(duration: 600.ms, delay: 200.ms)
            .slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic)
            .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),
          const SizedBox(height: 40),
          if (isPro) 
            _buildActiveBadge()
              .animate()
              .fadeIn(duration: 500.ms, delay: 400.ms)
              .scale(begin: const Offset(0, 0), end: const Offset(1, 1), curve: Curves.elasticOut)
              .shimmer(duration: 2000.ms, delay: 600.ms, color: Colors.green.withOpacity(0.3))
          else 
            _buildHeroOffer()
              .animate()
              .fadeIn(duration: 500.ms, delay: 400.ms)
              .slideY(begin: 0.2, end: 0),
        ],
      ),
    );
  }

  Widget _buildActiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00E676), Color(0xFF00C853)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, color: Colors.white, size: 22),
          SizedBox(width: 10),
          Text(
            'PRO MEMBER',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroOffer() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withOpacity(0.2),
                AppColors.primary.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 15,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              const Text(
                'SPECIAL APP LAUNCH OFFER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        )
          .animate()
          .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1), curve: Curves.elasticOut)
          .shimmer(duration: 2000.ms, delay: 600.ms, color: AppColors.primary.withOpacity(0.3)),
        const SizedBox(height: 16),
        const Text(
          'Empower your game with professional data\nand live broadcasting tools.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: Colors.white70,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildInteractivePlans(bool isPro) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 20),
            child: Text(
              'Select Your Path',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          )
            .animate()
            .fadeIn(duration: 400.ms, delay: 100.ms)
            .slideX(begin: -0.2, end: 0),
          Row(
            children: [
              Expanded(
                child: _buildEnhancedPlanCard(
                  title: 'BASIC',
                  price: '₹0',
                  isSelected: _selectedPlan == 'basic',
                  onTap: () => setState(() => _selectedPlan = 'basic'),
                  features: ['Scoring', 'Profile'],
                  isProCard: false,
                )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 200.ms)
                  .slideX(begin: -0.3, end: 0, curve: Curves.easeOutCubic)
                  .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildEnhancedPlanCard(
                  title: 'PRO',
                  price: '₹999',
                  period: '/yr',
                  isSelected: _selectedPlan == 'pro',
                  onTap: () => setState(() => _selectedPlan = 'pro'),
                  features: ['Live Streaming', 'Analytics', 'MVP Data'],
                  isProCard: true,
                  badge: 'BEST VALUE',
                )
                  .animate()
                  .fadeIn(duration: 500.ms, delay: 300.ms)
                  .slideX(begin: 0.3, end: 0, curve: Curves.easeOutCubic)
                  .scale(begin: const Offset(0.9, 0.9), end: const Offset(1, 1))
                  .then(delay: 400.ms)
                  .shimmer(duration: 2000.ms, color: AppColors.primary.withOpacity(0.3)),
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (!isPro) 
            _buildModernSubscribeButton()
              .animate()
              .fadeIn(duration: 500.ms, delay: 500.ms)
              .slideY(begin: 0.3, end: 0, curve: Curves.easeOutCubic)
              .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1)),
        ],
      ),
    );
  }

  Widget _buildEnhancedPlanCard({
    required String title,
    required String price,
    String period = '',
    required bool isSelected,
    required VoidCallback onTap,
    required List<String> features,
    required bool isProCard,
    String? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: isProCard && isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1E3A5F),
                    const Color(0xFF0F1F3A),
                    const Color(0xFF0A1529),
                  ],
                )
              : null,
          color: isProCard && isSelected 
              ? null 
              : (isSelected ? const Color(0xFF1A1F2E) : const Color(0xFF151925)),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: isSelected 
                ? (isProCard 
                    ? AppColors.primary 
                    : Colors.white.withOpacity(0.3))
                : Colors.white.withOpacity(0.1),
            width: isSelected ? (isProCard ? 3 : 2) : 1.5,
          ),
          boxShadow: [
            if (isSelected && isProCard)
              BoxShadow(
                color: AppColors.primary.withOpacity(0.5),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, 15),
              )
            else if (isSelected)
              BoxShadow(
                color: Colors.white.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: Column(
          children: [
            if (badge != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF9800), Color(0xFFFF5722)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF9800).withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      badge,
                      style: const TextStyle(
                        color: Colors.white, 
                        fontSize: 10, 
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              )
                .animate()
                .scale(begin: const Offset(0, 0), end: const Offset(1, 1), curve: Curves.elasticOut)
                .shimmer(duration: 2000.ms, delay: 500.ms, color: Colors.orange.withOpacity(0.5)),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: isProCard 
                    ? (isSelected ? Colors.white : AppColors.primary)
                    : (isSelected ? Colors.white : Colors.white70),
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: price,
                    style: TextStyle(
                      fontSize: 32, 
                      fontWeight: FontWeight.w900, 
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                  if (period.isNotEmpty)
                    TextSpan(
                      text: period,
                      style: TextStyle(
                        fontSize: 14, 
                        color: Colors.white.withOpacity(0.6), 
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ...features.asMap().entries.map((entry) {
              final index = entry.key;
              final f = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isProCard 
                            ? AppColors.primary.withOpacity(0.2)
                            : Colors.green.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_circle_rounded, 
                        size: 18, 
                        color: isProCard ? AppColors.primary : Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        f,
                        style: TextStyle(
                          fontSize: 13, 
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
                  .animate()
                  .fadeIn(duration: 300.ms, delay: (index * 100).ms)
                  .slideX(begin: -0.2, end: 0),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildModernSubscribeButton() {
    final isProSelected = _selectedPlan == 'pro';
    
    return Container(
      width: double.infinity,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: isProSelected 
            ? const LinearGradient(
                colors: [Color(0xFF007AFF), Color(0xFF0051FF)],
              )
            : null,
        color: !isProSelected ? Colors.grey[200] : null,
        boxShadow: [
          if (isProSelected)
            BoxShadow(
              color: const Color(0xFF007AFF).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : (isProSelected ? _handlePayment : null),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24, 
                height: 24, 
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isProSelected) const Icon(Icons.bolt, color: Colors.white),
                  if (isProSelected) const SizedBox(width: 8),
                  Text(
                    isProSelected ? 'Get Unlimited Access' : 'Selected Basic Plan',
                    style: TextStyle(
                      fontSize: 17, 
                      fontWeight: FontWeight.w900,
                      color: isProSelected ? Colors.white : Colors.black45,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildEnhancedBenefitsList() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildModernBenefitItem(
            icon: Icons.auto_graph_rounded,
            title: 'Advanced Analytics',
            description: 'Get deep insights into your batting & bowling metrics.',
            color: Colors.blue,
            index: 0,
          ),
          const SizedBox(height: 20),
          _buildModernBenefitItem(
            icon: Icons.videocam_rounded,
            title: 'Live Streaming',
            description: 'Broadcast your local matches with pro scoreboard overlays.',
            color: Colors.red,
            index: 1,
          ),
          const SizedBox(height: 20),
          _buildModernBenefitItem(
            icon: Icons.card_membership_rounded,
            title: 'Tourney Discounts',
            description: 'Enjoy exclusive entry fee discounts on major tournaments.',
            color: Colors.orange,
            index: 2,
          ),
          const SizedBox(height: 20),
          _buildModernBenefitItem(
            icon: Icons.stars_rounded,
            title: 'MVP Spotlight',
            description: 'Enhanced visibility in regional leaderboards & MVP lists.',
            color: Colors.purple,
            isNew: true,
            index: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildModernBenefitItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    bool isNew = false,
    required int index,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A1F2E),
            const Color(0xFF151925),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 15,
            spreadRadius: 1,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.2),
                  color.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withOpacity(0.3), width: 1),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 30),
          )
            .animate()
            .scale(begin: const Offset(0, 0), end: const Offset(1, 1), curve: Curves.elasticOut),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (isNew) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.purple, Colors.purple.shade700],
                          ),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purple.withOpacity(0.4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
      .animate()
      .fadeIn(duration: 500.ms, delay: (700 + index * 150).ms)
      .slideX(begin: -0.3, end: 0, duration: 500.ms, delay: (700 + index * 150).ms, curve: Curves.easeOutCubic)
      .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1), duration: 500.ms, delay: (700 + index * 150).ms);
  }

  Widget _buildSectionHeader(String title) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star, size: 14, color: AppColors.primary.withOpacity(0.8)),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.star, size: 14, color: AppColors.primary.withOpacity(0.8)),
          ],
        ),
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 28),
          height: 2,
          width: 60,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                AppColors.primary.withOpacity(0.6),
                Colors.transparent,
              ],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  Widget _buildBranding() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_cricket, color: AppColors.primary, size: 28)
              .animate()
              .rotate(begin: -0.3, end: 0, duration: 800.ms, delay: 100.ms),
            const SizedBox(width: 12),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Colors.white, AppColors.primary, Colors.white],
              ).createShader(bounds),
              child: const Text(
                'PitchPoint',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontStyle: FontStyle.italic,
                  letterSpacing: -0.5,
                ),
              ),
            )
              .animate()
              .shimmer(duration: 2000.ms, delay: 300.ms, color: AppColors.primary.withOpacity(0.5)),
            const SizedBox(width: 12),
            Icon(Icons.sports_cricket, color: AppColors.primary, size: 28)
              .animate()
              .rotate(begin: 0.3, end: 0, duration: 800.ms, delay: 200.ms),
          ],
        ),
        const SizedBox(height: 8),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [
              Colors.white.withOpacity(0.9),
              Colors.white.withOpacity(0.7),
            ],
          ).createShader(bounds),
          child: Text(
            'MEMBER',
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 6,
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroText() {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF00D4FF), AppColors.primary, Color(0xFF0066FF), Color(0xFF00D4FF)],
            stops: [0.0, 0.3, 0.7, 1.0],
          ).createShader(bounds),
          child: const Text(
            'PLAY LIKE',
            style: TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 0.9,
              letterSpacing: -1.5,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        )
          .animate()
          .shimmer(duration: 3000.ms, delay: 500.ms, color: Colors.white.withOpacity(0.3)),
        const SizedBox(height: 8),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppColors.primary, Color(0xFF00D4FF), Color(0xFF0066FF), AppColors.primary],
            stops: [0.0, 0.3, 0.7, 1.0],
          ).createShader(bounds),
          child: const Text(
            'A PRO',
            style: TextStyle(
              fontSize: 52,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 0.9,
              letterSpacing: -1.5,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        )
          .animate()
          .shimmer(duration: 3000.ms, delay: 700.ms, color: Colors.white.withOpacity(0.3)),
      ],
    );
  }

  Widget _buildBenefitItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 24, color: AppColors.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SunburstPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.4);
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.fill;
      
    canvas.drawCircle(center, size.width * 0.3, paint);
    canvas.drawCircle(center, size.width * 0.6, paint..color = Colors.white.withOpacity(0.1));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Cricket-themed decorative widgets
Widget _buildCommentaryMic() {
  return Container(
    width: 60,
    height: 60,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          AppColors.primary.withOpacity(0.3),
          AppColors.primary.withOpacity(0.1),
          Colors.transparent,
        ],
      ),
    ),
    child: Icon(
      Icons.mic,
      color: AppColors.primary.withOpacity(0.7),
      size: 36,
    ),
  );
}

Widget _buildCommentarySpeaker() {
  return Container(
    width: 60,
    height: 60,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          AppColors.primary.withOpacity(0.3),
          AppColors.primary.withOpacity(0.1),
          Colors.transparent,
        ],
      ),
    ),
    child: Icon(
      Icons.graphic_eq,
      color: AppColors.primary.withOpacity(0.7),
      size: 36,
    ),
  );
}

Widget _buildCricketBall() {
  return Container(
    width: 50,
    height: 50,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          const Color(0xFFFFD700).withOpacity(0.4),
          const Color(0xFFFFA500).withOpacity(0.2),
          Colors.transparent,
        ],
      ),
    ),
    child: Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF8B4513).withOpacity(0.6),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );
}

Widget _buildFloatingCricketBall(int index) {
  final positions = [
    const Offset(50, 120),
    const Offset(300, 80),
    const Offset(80, 200),
    const Offset(280, 180),
    const Offset(120, 250),
    const Offset(250, 220),
    const Offset(60, 300),
    const Offset(320, 280),
  ];
  
  final delays = [100, 200, 300, 400, 500, 600, 700, 800];
  final sizes = [16.0, 20.0, 18.0, 22.0, 16.0, 20.0, 18.0, 22.0];
  
  return Positioned(
    left: positions[index].dx,
    top: positions[index].dy,
    child: Container(
      width: sizes[index],
      height: sizes[index],
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            const Color(0xFFFFD700).withOpacity(0.5),
            const Color(0xFFFFA500).withOpacity(0.3),
          ],
        ),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: sizes[index] * 0.3,
          height: sizes[index] * 0.3,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF8B4513).withOpacity(0.8),
          ),
        ),
      ),
    )
      .animate()
      .fadeIn(duration: 1000.ms, delay: delays[index].ms)
      .scale(begin: const Offset(0, 0), end: const Offset(1, 1), curve: Curves.elasticOut)
      .then()
      .shimmer(duration: 2000.ms, color: AppColors.primary.withOpacity(0.5)),
  );
}

Widget _buildSmallCricketBall() {
  return Container(
    width: 28,
    height: 28,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          const Color(0xFFFFD700).withOpacity(0.6),
          const Color(0xFFFFA500).withOpacity(0.4),
        ],
      ),
      border: Border.all(
        color: AppColors.primary.withOpacity(0.5),
        width: 2,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withOpacity(0.3),
          blurRadius: 8,
          spreadRadius: 1,
        ),
      ],
    ),
    child: Center(
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF8B4513).withOpacity(0.9),
        ),
      ),
    ),
  );
}

Widget _buildTinyCricketBall() {
  return Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          const Color(0xFFFFD700).withOpacity(0.7),
          const Color(0xFFFFA500).withOpacity(0.5),
        ],
      ),
      border: Border.all(
        color: AppColors.primary.withOpacity(0.6),
        width: 1,
      ),
    ),
    child: Center(
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF8B4513).withOpacity(0.9),
        ),
      ),
    ),
  );
}
