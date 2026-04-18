import 'package:flutter_test/flutter_test.dart';
import 'package:koala/widgets/swipe/swipe_math.dart';

/// Regression suite for SwipeMath. These tests pin the exact numeric
/// behaviour of the production swipe engine — a change here should be a
/// deliberate product decision (update the test AND ship the tuning),
/// never an accidental side-effect of a refactor.
void main() {
  group('velocityMultiplier', () {
    test('button tap (v=0) is treated as deliberate (1.0)', () {
      expect(SwipeMath.velocityMultiplier(0), 1.0);
    });

    test('slow / hesitant drag band yields 0.7', () {
      expect(SwipeMath.velocityMultiplier(200), 0.7);
      expect(SwipeMath.velocityMultiplier(499), 0.7);
    });

    test('normal swipe band yields 1.0', () {
      expect(SwipeMath.velocityMultiplier(500), 1.0);
      expect(SwipeMath.velocityMultiplier(999), 1.0);
    });

    test('fast flick yields 1.3', () {
      expect(SwipeMath.velocityMultiplier(1000), 1.3);
      expect(SwipeMath.velocityMultiplier(5000), 1.3);
    });

    test('negative velocity is absolute-valued (direction handled elsewhere)',
        () {
      expect(SwipeMath.velocityMultiplier(-1200), 1.3);
      expect(SwipeMath.velocityMultiplier(-300), 0.7);
    });
  });

  group('commitDirection', () {
    test('below threshold both ways → 0 (snap back)', () {
      expect(SwipeMath.commitDirection(dragDx: 89, velocity: 699), 0);
      expect(SwipeMath.commitDirection(dragDx: -89, velocity: -699), 0);
    });

    test('drag past +90 commits right even with no velocity', () {
      expect(SwipeMath.commitDirection(dragDx: 91, velocity: 0), 1);
    });

    test('drag past -90 commits left even with no velocity', () {
      expect(SwipeMath.commitDirection(dragDx: -91, velocity: 0), -1);
    });

    test('fast fling wins even with tiny drag', () {
      expect(SwipeMath.commitDirection(dragDx: 0, velocity: 701), 1);
      expect(SwipeMath.commitDirection(dragDx: 0, velocity: -701), -1);
    });

    test('drag and velocity agree → commit fires once', () {
      expect(SwipeMath.commitDirection(dragDx: 200, velocity: 1500), 1);
    });
  });

  group('rotationForDx / swipeRatio', () {
    test('rotation at dx=600 is exactly 1 radian (legacy feel)', () {
      expect(SwipeMath.rotationForDx(600), 1.0);
    });

    test('rotation is linear and centered on zero', () {
      expect(SwipeMath.rotationForDx(0), 0);
      expect(SwipeMath.rotationForDx(-300), -0.5);
    });

    test('overlay ratio clamps to [-1, 1]', () {
      expect(SwipeMath.swipeRatio(120), 1.0);
      expect(SwipeMath.swipeRatio(-120), -1.0);
      expect(SwipeMath.swipeRatio(999), 1.0);
      expect(SwipeMath.swipeRatio(-999), -1.0);
    });

    test('partial drag yields partial ratio', () {
      expect(SwipeMath.swipeRatio(60), closeTo(0.5, 1e-9));
      expect(SwipeMath.swipeRatio(-30), closeTo(-0.25, 1e-9));
    });
  });

  group('exit kinematics', () {
    test('button-tap exit starts at the min offset, sign-matched', () {
      expect(SwipeMath.exitStartDx(currentDragDx: 0, liked: true), 24);
      expect(SwipeMath.exitStartDx(currentDragDx: 0, liked: false), -24);
    });

    test('exit start preserves existing drag when it is past the threshold',
        () {
      expect(
        SwipeMath.exitStartDx(currentDragDx: 150, liked: true),
        150,
      );
      expect(
        SwipeMath.exitStartDx(currentDragDx: -150, liked: false),
        -150,
      );
    });

    test('exit target is 1.4× screen width, sign-matched', () {
      expect(
        SwipeMath.exitTargetDx(screenWidth: 400, liked: true),
        closeTo(560, 1e-9),
      );
      expect(
        SwipeMath.exitTargetDx(screenWidth: 400, liked: false),
        closeTo(-560, 1e-9),
      );
    });

    test('lerp clamps to [0,1]', () {
      expect(SwipeMath.lerp(0, 100, 0), 0);
      expect(SwipeMath.lerp(0, 100, 1), 100);
      expect(SwipeMath.lerp(0, 100, 0.5), 50);
      expect(SwipeMath.lerp(0, 100, -0.3), 0);
      expect(SwipeMath.lerp(0, 100, 1.7), 100);
    });
  });

  group('dampened dy', () {
    test('vertical drag is scaled by 0.3', () {
      expect(SwipeMath.dampenedDy(100), closeTo(30, 1e-9));
      expect(SwipeMath.dampenedDy(-50), closeTo(-15, 1e-9));
      expect(SwipeMath.dampenedDy(0), 0);
    });
  });

  group('isSaveIntent', () {
    test('downward motion is never save intent', () {
      expect(SwipeMath.isSaveIntent(dragDx: 0, dragDy: 200), false);
      expect(SwipeMath.isSaveIntent(dragDx: 50, dragDy: 100), false);
    });

    test('tiny upward motion is noise, not save intent', () {
      expect(SwipeMath.isSaveIntent(dragDx: 0, dragDy: -20), false);
    });

    test('clear upward motion with no horizontal is save intent', () {
      expect(SwipeMath.isSaveIntent(dragDx: 0, dragDy: -60), true);
      expect(SwipeMath.isSaveIntent(dragDx: 5, dragDy: -80), true);
    });

    test('horizontal-dominant diagonal is not save intent', () {
      // Up 50, right 80 → user is going right, not up
      expect(SwipeMath.isSaveIntent(dragDx: 80, dragDy: -50), false);
    });

    test('vertical-dominant diagonal still counts as save', () {
      // Up 100, right 30 → mostly up
      expect(SwipeMath.isSaveIntent(dragDx: 30, dragDy: -100), true);
    });
  });

  group('commitAxis', () {
    test('below all thresholds → none (snap back)', () {
      expect(
        SwipeMath.commitAxis(
          dragDx: 50,
          dragDy: -50,
          velocityX: 100,
          velocityY: -100,
        ),
        SwipeAxis.none,
      );
    });

    test('horizontal-only drag picks right/left', () {
      expect(
        SwipeMath.commitAxis(
          dragDx: 120,
          dragDy: 0,
          velocityX: 0,
          velocityY: 0,
        ),
        SwipeAxis.right,
      );
      expect(
        SwipeMath.commitAxis(
          dragDx: -120,
          dragDy: 0,
          velocityX: 0,
          velocityY: 0,
        ),
        SwipeAxis.left,
      );
    });

    test('upward-only drag past threshold picks up (save)', () {
      expect(
        SwipeMath.commitAxis(
          dragDx: 0,
          dragDy: -150,
          velocityX: 0,
          velocityY: 0,
        ),
        SwipeAxis.up,
      );
    });

    test('fast upward fling wins regardless of distance', () {
      expect(
        SwipeMath.commitAxis(
          dragDx: 0,
          dragDy: -40,
          velocityX: 0,
          velocityY: -950,
        ),
        SwipeAxis.up,
      );
    });

    test('diagonal both-past-threshold picks larger magnitude', () {
      // Horizontal wins (|dx|=200 > |dy|=150)
      expect(
        SwipeMath.commitAxis(
          dragDx: 200,
          dragDy: -150,
          velocityX: 0,
          velocityY: 0,
        ),
        SwipeAxis.right,
      );
      // Vertical wins (|dy|=300 > |dx|=120)
      expect(
        SwipeMath.commitAxis(
          dragDx: 120,
          dragDy: -300,
          velocityX: 0,
          velocityY: 0,
        ),
        SwipeAxis.up,
      );
    });

    test('downward drag never commits (there is no down gesture)', () {
      expect(
        SwipeMath.commitAxis(
          dragDx: 0,
          dragDy: 300,
          velocityX: 0,
          velocityY: 2000,
        ),
        SwipeAxis.none,
      );
    });
  });

  group('saveRatio / save exit', () {
    test('downward motion yields zero save ratio', () {
      expect(SwipeMath.saveRatio(50), 0);
      expect(SwipeMath.saveRatio(0), 0);
    });

    test('save ratio saturates at the configured distance', () {
      expect(SwipeMath.saveRatio(-140), 1.0);
      expect(SwipeMath.saveRatio(-500), 1.0);
    });

    test('partial upward drag yields partial save ratio', () {
      expect(SwipeMath.saveRatio(-70), closeTo(0.5, 1e-9));
      expect(SwipeMath.saveRatio(-35), closeTo(0.25, 1e-9));
    });

    test('exit target dy is negative and scales with screen height', () {
      expect(
        SwipeMath.exitTargetDy(screenHeight: 800),
        closeTo(-1040, 1e-9),
      );
    });

    test('save exit start biases upward when drag is small', () {
      expect(
        SwipeMath.saveExitStartDy(currentDragDy: 0),
        -24,
      );
      expect(
        SwipeMath.saveExitStartDy(currentDragDy: -10),
        -24,
      );
    });

    test('save exit start preserves drag once past the threshold', () {
      expect(
        SwipeMath.saveExitStartDy(currentDragDy: -80),
        -80,
      );
    });
  });

  group('hapticLevel (progressive thresholds)', () {
    test('idle below the first threshold', () {
      expect(SwipeMath.hapticLevel(0), SwipeHaptic.idle);
      expect(SwipeMath.hapticLevel(0.39), SwipeHaptic.idle);
    });

    test('approach at 0.4+', () {
      expect(SwipeMath.hapticLevel(0.4), SwipeHaptic.approach);
      expect(SwipeMath.hapticLevel(0.69), SwipeHaptic.approach);
    });

    test('nearCommit at 0.7+', () {
      expect(SwipeMath.hapticLevel(0.7), SwipeHaptic.nearCommit);
      expect(SwipeMath.hapticLevel(0.99), SwipeHaptic.nearCommit);
    });

    test('commit at 1.0+', () {
      expect(SwipeMath.hapticLevel(1.0), SwipeHaptic.commit);
      expect(SwipeMath.hapticLevel(5.0), SwipeHaptic.commit);
    });
  });
}
