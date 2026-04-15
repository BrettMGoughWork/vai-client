import 'package:flutter/material.dart';

import '../content/content_renderer.dart';
import '../content/content_type.dart';
import 'chat_controller.dart';
import 'chat_turn.dart';
import 'shimmer_text.dart';

class ChatPage extends StatefulWidget {
  ChatPage({
    required this.controller,
    ContentRendererRegistry? contentRendererRegistry,
    super.key,
  }) : contentRendererRegistry =
            contentRendererRegistry ?? defaultContentRendererRegistry;

  final ChatController controller;
  final ContentRendererRegistry contentRendererRegistry;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _lastTurnCount = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        _scheduleScrollIfNeeded(widget.controller.turns.length);

        return Scaffold(
          backgroundColor: const Color(0xFF000000),
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          'Vai',
                          style: TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ),
                      _ConnectionIndicator(
                        state: widget.controller.connectionState,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    itemCount: widget.controller.turns.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(height: 22),
                    itemBuilder: (BuildContext context, int index) {
                      return _ChatTurnView(
                        turn: widget.controller.turns[index],
                        contentRendererRegistry: widget.contentRendererRegistry,
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF111111),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: TextField(
                            key: const Key('chat-input'),
                            controller: _textController,
                            minLines: 1,
                            maxLines: 5,
                            style: const TextStyle(color: Color(0xFFFFFFFF)),
                            cursorColor: const Color(0xFFFFFFFF),
                            decoration: const InputDecoration(
                              hintText: 'Ask Vai',
                              hintStyle: TextStyle(color: Color(0xFF6E6E6E)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                            ),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x33FFFFFF)),
                        ),
                        child: IconButton(
                          key: const Key('submit-button'),
                          onPressed: widget.controller.canSend ? _submit : null,
                          icon: Icon(
                            Icons.arrow_upward_rounded,
                            color: widget.controller.canSend
                                ? const Color(0xFFFFFFFF)
                                : const Color(0xFF5A5A5A),
                          ),
                          splashRadius: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scheduleScrollIfNeeded(int count) {
    if (count == _lastTurnCount) {
      return;
    }
    _lastTurnCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _submit() async {
    final String text = _textController.text;
    if (text.trim().isEmpty) {
      return;
    }

    _textController.clear();
    await widget.controller.sendPrompt(text);
  }
}

class _ChatTurnView extends StatelessWidget {
  const _ChatTurnView({
    required this.turn,
    required this.contentRendererRegistry,
  });

  final ChatTurn turn;
  final ContentRendererRegistry contentRendererRegistry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Text(
                  turn.prompt,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: child,
              ),
            );
          },
          child: _responseBodyForTurn(context, turn),
        ),
      ],
    );
  }

  Widget _responseBodyForTurn(BuildContext context, ChatTurn turn) {
    if (turn.finalContent != null) {
      return Align(
        key: ValueKey<String>('final-${turn.intentId}-${turn.finalContent!.type.wireName}'),
        alignment: Alignment.centerLeft,
        child: contentRendererRegistry.build(
          context,
          turn.finalContent!,
          isErrored: turn.isErrored,
        ),
      );
    }

    if (turn.partialText != null && turn.partialText!.isNotEmpty) {
      return Align(
        key: ValueKey<String>('partial-${turn.intentId}-${turn.partialText}'),
        alignment: Alignment.centerLeft,
        child: Opacity(
          opacity: 0.88,
          child: Text(
            turn.partialText!,
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    if (turn.isErrored && turn.errorMessage != null) {
      return Align(
        key: ValueKey<String>('error-${turn.intentId}'),
        alignment: Alignment.centerLeft,
        child: Text(
          turn.errorMessage!,
          style: const TextStyle(
            color: Color(0xFFFF6B6B),
            fontSize: 15,
            height: 1.4,
          ),
        ),
      );
    }

    if (turn.ephemeralLines.isNotEmpty) {
      return Align(
        key: ValueKey<String>('ephemeral-${turn.intentId}-${turn.ephemeralLines.length}'),
        alignment: Alignment.centerLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: List<Widget>.generate(turn.ephemeralLines.length, (int index) {
                final bool isLatest = index == turn.ephemeralLines.length - 1;
                const TextStyle style = TextStyle(
                  color: Color(0xFFB0B0B0),
                  fontSize: 13,
                  height: 1.35,
                );
                if (isLatest) {
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == turn.ephemeralLines.length - 1 ? 0 : 6,
                    ),
                    child: ShimmerText(
                      key: Key('ephemeral-shimmer-${turn.intentId}'),
                      text: turn.ephemeralLines[index],
                      style: style,
                    ),
                  );
                }
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == turn.ephemeralLines.length - 1 ? 0 : 6,
                  ),
                  child: Text(turn.ephemeralLines[index], style: style),
                );
              }),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      key: ValueKey<String>('empty-${turn.intentId}'),
      height: 2,
    );
  }
}

class _ConnectionIndicator extends StatelessWidget {
  const _ConnectionIndicator({required this.state});

  final ChatConnectionIndicatorState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x26FFFFFF)),
      ),
      alignment: Alignment.center,
      child: Container(
        key: const Key('connection-indicator-dot'),
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: _colorForState(state),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Color _colorForState(ChatConnectionIndicatorState state) {
    switch (state) {
      case ChatConnectionIndicatorState.connected:
        return const Color(0xFF2BD576);
      case ChatConnectionIndicatorState.pending:
        return const Color(0xFFFFA726);
      case ChatConnectionIndicatorState.unavailable:
        return const Color(0xFFF44336);
      case ChatConnectionIndicatorState.idle:
        return const Color(0xFF767676);
    }
  }
}
