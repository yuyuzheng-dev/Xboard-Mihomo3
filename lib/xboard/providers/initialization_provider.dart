import 'package:flutter_riverpod/flutter_riverpod.dart';

enum InitializationStatus {
  initializing,
  success,
  error,
}

class InitializationState {
  final InitializationStatus status;
  final String? errorMessage;

  InitializationState({required this.status, this.errorMessage});
}

class InitializationNotifier extends StateNotifier<InitializationState> {
  InitializationNotifier() : super(InitializationState(status: InitializationStatus.initializing));

  void setSuccess() {
    state = InitializationState(status: InitializationStatus.success);
  }

  void setError(String message) {
    state = InitializationState(status: InitializationStatus.error, errorMessage: message);
  }

  void setInitializing() {
    state = InitializationState(status: InitializationStatus.initializing);
  }
}

final initializationProvider = StateNotifierProvider<InitializationNotifier, InitializationState>(
  (ref) => InitializationNotifier(),
);
