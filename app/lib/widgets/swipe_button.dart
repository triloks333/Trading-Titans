import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SwipeButton extends StatefulWidget {
  final String text;
  final VoidCallback onSwipeComplete;
  final Color color;
  final bool isLoading;

  const SwipeButton({
    super.key,
    required this.text,
    required this.onSwipeComplete,
    required this.color,
    this.isLoading = false,
  });

  @override
  State<SwipeButton> createState() => _SwipeButtonState();
}

class _SwipeButtonState extends State<SwipeButton> with SingleTickerProviderStateMixin {
  double _dragPosition = 0.0;
  bool _isCompleted = false;
  late AnimationController _resetController;
  late Animation<double> _resetAnimation;
  final double _buttonHeight = 56.0;
  final double _thumbWidth = 56.0;

  @override
  void initState() {
    super.initState();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _resetAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _resetController, curve: Curves.easeOut),
    )..addListener(() {
        setState(() {
          _dragPosition = _resetAnimation.value;
        });
      });
  }

  @override
  void dispose() {
    _resetController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details, double containerWidth) {
    if (_isCompleted || widget.isLoading) return;
    setState(() {
      _dragPosition += details.delta.dx;
      if (_dragPosition < 0) _dragPosition = 0;
      if (_dragPosition > containerWidth - _thumbWidth) {
        _dragPosition = containerWidth - _thumbWidth;
      }
    });
  }

  void _onDragEnd(DragEndDetails details, double containerWidth) {
    if (_isCompleted || widget.isLoading) return;
    
    if (_dragPosition >= (containerWidth - _thumbWidth) * 0.8) {
      // Completed
      setState(() {
        _dragPosition = containerWidth - _thumbWidth;
        _isCompleted = true;
      });
      widget.onSwipeComplete();
      
      // Auto reset after 2 seconds (optional)
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _reset();
      });
    } else {
      _reset();
    }
  }

  void _reset() {
    _resetAnimation = Tween<double>(begin: _dragPosition, end: 0.0).animate(
      CurvedAnimation(parent: _resetController, curve: Curves.easeOut),
    );
    _resetController.forward(from: 0.0);
    setState(() {
      _isCompleted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _buttonHeight,
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: widget.isLoading ? 0.7 : 1.0),
        borderRadius: BorderRadius.circular(_buttonHeight / 2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final containerWidth = constraints.maxWidth;
          return Stack(
            children: [
              // Background Text
              Center(
                child: widget.isLoading 
                  ? const SizedBox(
                      width: 24, height: 24, 
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    )
                  : Text(
                      widget.text,
                      style: GoogleFonts.ibmPlexSans(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                    ),
              ),
              // Draggable Thumb
              if (!widget.isLoading)
                Positioned(
                  left: _dragPosition,
                  top: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) => _onDragUpdate(details, containerWidth),
                    onHorizontalDragEnd: (details) => _onDragEnd(details, containerWidth),
                    child: Container(
                      width: _thumbWidth,
                      height: _buttonHeight,
                      margin: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: widget.color,
                        size: 32,
                      ),
                    ),
                  ),
                ),
            ],
          );
        }
      ),
    );
  }
}
