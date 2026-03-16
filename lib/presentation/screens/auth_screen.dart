import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/di/service_locator.dart';
import '../cubit/auth_cubit.dart';
import '../cubit/auth_state.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();

  final _loginUsernameController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  final _signupDisplayNameController = TextEditingController();
  final _signupUsernameController = TextEditingController();
  final _signupPasswordController = TextEditingController();

  bool _loginObscurePassword = true;
  bool _signupObscurePassword = true;

  String? _selectedAvatarSeed;

  static const List<String> _avatarSeeds = <String>[
    'Oreo',
    'Milo',
    'Peanut',
    'Bella',
    'Loki',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginUsernameController.dispose();
    _loginPasswordController.dispose();
    _signupDisplayNameController.dispose();
    _signupUsernameController.dispose();
    _signupPasswordController.dispose();
    super.dispose();
  }

  String? _validateDisplayName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Display name is required';
    }
    if (value.trim().length < 2) {
      return 'Display name must be at least 2 characters';
    }
    return null;
  }

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Username is required';
    }
    if (value.trim().length < 4) {
      return 'Username must be at least 4 characters';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  void _onLogin(AuthCubit cubit, AuthState state) {
    if (_loginFormKey.currentState?.validate() != true || state.isLoading) {
      return;
    }
    final username = _loginUsernameController.text.trim();
    final password = _loginPasswordController.text;
    cubit.login(username: username, password: password);
  }

  void _onSignUp(AuthCubit cubit, AuthState state) {
    if (_signupFormKey.currentState?.validate() != true || state.isLoading) {
      return;
    }
    final displayName = _signupDisplayNameController.text.trim();
    final username = _signupUsernameController.text.trim();
    final password = _signupPasswordController.text;
    final avatarUrl = _selectedAvatarSeed == null
        ? null
        : 'https://api.dicebear.com/7.x/thumbs/svg?seed=$_selectedAvatarSeed';

    cubit.registerAndLogin(
      username: username,
      password: password,
      displayName: displayName,
      avatarUrl: avatarUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoginTab = _tabController.index == 0;
    final titleText = isLoginTab ? 'Sign in' : 'Create account';

    return BlocProvider<AuthCubit>(
      create: (_) => getIt<AuthCubit>()..checkExistingSession(),
      child: BlocConsumer<AuthCubit, AuthState>(
        listener: (BuildContext context, AuthState state) {
          if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage!),
                  backgroundColor: Colors.redAccent,
                ),
              );
          }

          if (state.isAuthenticated) {
            context.goNamed(AppRouter.chats);
          }
        },
        builder: (BuildContext context, AuthState state) {
          return Scaffold(
            backgroundColor: AppColors.scaffold,
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.1),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                          child: Text(
                            titleText,
                            key: ValueKey<String>(titleText),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Welcome to WhatsApp Clone',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.appBar,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            indicator: BoxDecoration(
                              color: AppColors.scaffold,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            labelColor: AppColors.textPrimary,
                            unselectedLabelColor: AppColors.textSecondary,
                            tabs: const <Widget>[
                              Tab(text: 'Login'),
                              Tab(text: 'Sign up'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 420,
                          child: TabBarView(
                            controller: _tabController,
                            children: <Widget>[
                              _buildLoginForm(context, state),
                              _buildSignUpForm(context, state),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context, AuthState state) {
    final cubit = context.read<AuthCubit>();

    return SingleChildScrollView(
      child: Form(
        key: _loginFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildLabel('Username'),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _loginUsernameController,
              hintText: 'Enter your username',
              validator: _validateUsername,
            ),
            const SizedBox(height: 16),
            _buildLabel('Password'),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _loginPasswordController,
              hintText: 'Enter your password',
              obscureText: _loginObscurePassword,
              validator: _validatePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _loginObscurePassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: AppColors.iconMuted,
                ),
                onPressed: () {
                  setState(() {
                    _loginObscurePassword = !_loginObscurePassword;
                  });
                },
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: state.isLoading
                    ? null
                    : () => _onLogin(cubit, state),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: state.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.black,
                          ),
                        ),
                      )
                    : const Text(
                        'Sign in',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSignUpForm(BuildContext context, AuthState state) {
    final cubit = context.read<AuthCubit>();

    return SingleChildScrollView(
      child: Form(
        key: _signupFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _buildLabel('Choose avatar (optional)'),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  ..._avatarSeeds.map(_buildAvatarItem),
                  const SizedBox(width: 12),
                  _buildUploadAvatarPlaceholder(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildLabel('Display name'),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _signupDisplayNameController,
              hintText: 'Enter your name',
              validator: _validateDisplayName,
            ),
            const SizedBox(height: 16),
            _buildLabel('Username'),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _signupUsernameController,
              hintText: 'Choose a username',
              validator: _validateUsername,
            ),
            const SizedBox(height: 16),
            _buildLabel('Password'),
            const SizedBox(height: 8),
            _buildTextField(
              controller: _signupPasswordController,
              hintText: 'Create a password',
              obscureText: _signupObscurePassword,
              validator: _validatePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _signupObscurePassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: AppColors.iconMuted,
                ),
                onPressed: () {
                  setState(() {
                    _signupObscurePassword = !_signupObscurePassword;
                  });
                },
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: state.isLoading
                    ? null
                    : () => _onSignUp(cubit, state),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: state.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.black,
                          ),
                        ),
                      )
                    : const Text(
                        'Sign up',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required String? Function(String?) validator,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: AppColors.textPrimary),
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.inputBar,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildAvatarItem(String seed) {
    final isSelected = _selectedAvatarSeed == seed;
    final avatarUrl = 'https://api.dicebear.com/7.x/thumbs/svg?seed=$seed';

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedAvatarSeed = seed;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.divider,
            width: isSelected ? 2.5 : 1,
          ),
        ),
        child: CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.chatBackground,
          child: ClipOval(
            child: SvgPicture.network(
              avatarUrl,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadAvatarPlaceholder() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.divider,
          width: 1.5,
          style: BorderStyle.solid,
        ),
      ),
      child: const Center(
        child: Icon(Icons.upload, color: AppColors.iconMuted, size: 22),
      ),
    );
  }
}
