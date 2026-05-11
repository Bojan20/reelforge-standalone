// lua_bridge_test.dart
// Tests for LuaBridge — real Lua VM via `lua` package (petitparser-based).
// Tests: VM init, basic expressions, control flow, tables, print output,
//        FluxForge API binding, error handling.
//
// Note on whitespace: the lua package block parser uses `(\n|;).star()` as
// statement separator. Leading spaces after a newline confuse it, so multiline
// scripts must not have indented lines. Use the `s()` helper to strip them.

import 'package:flutter_test/flutter_test.dart';
import 'package:lua/lua.dart';

/// Strip leading whitespace from each line so multi-line script literals
/// work regardless of how they are indented in the source file.
String s(String code) =>
    code.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).join('\n');

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Direct lua package tests (no FluxForge deps — pure VM verification)
  // ─────────────────────────────────────────────────────────────────────────

  group('Lua VM — basic expressions', () {
    test('return numeric literal', () {
      final result = parse('return 42').evaluate();
      expect(result, equals(42));
    });

    test('return string literal', () {
      final result = parse('return "hello"').evaluate();
      expect(result, equals('hello'));
    });

    test('return boolean true', () {
      final result = parse('return true').evaluate();
      expect(result, isTrue);
    });

    test('return nil', () {
      final result = parse('return nil').evaluate();
      expect(result, isNull);
    });

    test('arithmetic', () {
      final result = parse('return 3 + 4 * 2').evaluate();
      expect(result, equals(11));
    });

    test('string concatenation', () {
      final result = parse('return "foo" .. "bar"').evaluate();
      expect(result, equals('foobar'));
    });
  });

  group('Lua VM — variables and assignment', () {
    test('local variable', () {
      final result = parse(s('''
        local x = 10
        return x
      ''')).evaluate();
      expect(result, equals(10));
    });

    test('multiple assignments', () {
      final result = parse(s('''
        local a = 3
        local b = 7
        return a + b
      ''')).evaluate();
      expect(result, equals(10));
    });

    test('env variable injection', () {
      final env = LuaEnv(variables: {'myVar': 99});
      final result = parse('return myVar').evaluate(env: env);
      expect(result, equals(99));
    });
  });

  group('Lua VM — control flow', () {
    test('if true branch taken', () {
      final result = parse(s('''
        local x = 0
        if true then
        x = 1
        end
        return x
      ''')).evaluate();
      expect(result, equals(1));
    });

    test('if/else false branch taken', () {
      final result = parse(s('''
        local x = 0
        if false then
        x = 1
        else
        x = 2
        end
        return x
      ''')).evaluate();
      expect(result, equals(2));
    });

    test('numeric for loop', () {
      final result = parse(s('''
        local sum = 0
        for i = 1, 5 do
        sum = sum + i
        end
        return sum
      ''')).evaluate();
      expect(result, equals(15)); // 1+2+3+4+5
    });

    test('while loop', () {
      final result = parse(s('''
        local n = 0
        local i = 0
        while i < 4 do
        n = n + i
        i = i + 1
        end
        return n
      ''')).evaluate();
      expect(result, equals(6)); // 0+1+2+3
    });
  });

  group('Lua VM — functions', () {
    test('inline function definition and call', () {
      final result = parse(s('''
        local function double(x)
        return x * 2
        end
        return double(21)
      ''')).evaluate();
      expect(result, equals(42));
    });

    // Note: lua 0.2.0 has a stack issue with deeply recursive calls.
    // Use iterative factorial instead to verify function + loop composition.
    test('iterative function (fact via for loop)', () {
      final result = parse(s('''
        local function fact(n)
        local result = 1
        for i = 2, n do
        result = result * i
        end
        return result
        end
        return fact(5)
      ''')).evaluate();
      expect(result, equals(120));
    });
  });

  group('Lua VM — tables', () {
    // Table field assignment (t.x = val) is NOT supported by lua 0.2.0.
    // Use constructors {key=val} for initialization.

    test('table constructor named field read', () {
      final result = parse('local t = {x = 42}\nreturn t.x').evaluate();
      expect(result, equals(42));
    });

    test('table constructor multiple named fields', () {
      final result = parse('local t = {a = 10, b = 32}\nreturn t.a + t.b').evaluate();
      expect(result, equals(42));
    });

    test('table constructor array read via index', () {
      final result = parse('local t = {10, 20, 30}\nreturn t[2]').evaluate();
      expect(result, equals(20));
    });

    test('TableInstance injected from Dart as variable', () {
      final t = TableInstance();
      t.fields['x'] = 99;
      final env = LuaEnv(variables: {'t': t});
      final result = parse('return t.x').evaluate(env: env);
      expect(result, equals(99));
    });
  });

  group('Lua VM — print output', () {
    test('print captures to output buffer', () {
      final buf = LuaOutputBuffer();
      final env = LuaEnv.withStdlib(output: buf);
      parse('print("hello world")').evaluate(env: env);
      expect(buf.output.trim(), equals('hello world'));
    });

    test('multiple print calls', () {
      final buf = LuaOutputBuffer();
      final env = LuaEnv.withStdlib(output: buf);
      parse('print("line1")\nprint("line2")').evaluate(env: env);
      expect(buf.output, contains('line1'));
      expect(buf.output, contains('line2'));
    });
  });

  group('Lua VM — custom builtin injection', () {
    test('custom Dart function callable from Lua', () {
      int callCount = 0;
      final env = LuaEnv(builtins: {
        'increment': (List<Object?> args) {
          callCount++;
          return callCount;
        },
      });
      parse('increment()').evaluate(env: env);
      parse('increment()').evaluate(env: env);
      expect(callCount, equals(2));
    });

    test('custom function receives arguments', () {
      double? receivedValue;
      final env = LuaEnv(builtins: {
        'setValue': (List<Object?> args) {
          receivedValue = (args.first as num?)?.toDouble();
          return null;
        },
      });
      parse('setValue(3.14)').evaluate(env: env);
      expect(receivedValue, closeTo(3.14, 0.001));
    });
  });

  group('Lua VM — fluxforge table via TableInstance', () {
    // Verify that fluxforge.X() namespace works without needing real FluxForge providers

    test('fluxforge table method callable', () {
      bool triggered = false;
      String? triggeredStage;

      final fluxforgeTable = TableInstance();
      fluxforgeTable.fields['triggerStage'] = (List<Object?> args) {
        triggered = true;
        triggeredStage = args.isNotEmpty ? args[0] as String? : null;
        return null;
      };

      final env = LuaEnv(variables: {'fluxforge': fluxforgeTable});
      parse('fluxforge.triggerStage("UI_SPIN_PRESS")').evaluate(env: env);

      expect(triggered, isTrue);
      expect(triggeredStage, equals('UI_SPIN_PRESS'));
    });

    test('fluxforge.print captures output', () {
      final buf = LuaOutputBuffer();
      final fluxforgeTable = TableInstance();
      fluxforgeTable.fields['print'] = (List<Object?> args) {
        final msg = args.map((a) => a?.toString() ?? 'nil').join('\t');
        buf.writeLine(msg);
        return null;
      };

      final env = LuaEnv(
        variables: {'fluxforge': fluxforgeTable},
        output: buf,
      );
      parse('fluxforge.print("test output")').evaluate(env: env);

      expect(buf.output, contains('test output'));
    });

    test('fluxforge API in loop', () {
      final calls = <String>[];
      final fluxforgeTable = TableInstance();
      fluxforgeTable.fields['triggerStage'] = (List<Object?> args) {
        calls.add(args[0] as String);
        return null;
      };

      final env = LuaEnv(variables: {'fluxforge': fluxforgeTable});
      // Use \n separator — no indentation
      parse(s('''
        local stages = {"STAGE_A", "STAGE_B", "STAGE_C"}
        for i = 1, 3 do
        fluxforge.triggerStage(stages[i])
        end
      ''')).evaluate(env: env);

      expect(calls, equals(['STAGE_A', 'STAGE_B', 'STAGE_C']));
    });

    test('fluxforge setRtpc receives numeric value', () {
      String? rtpcId;
      double? rtpcValue;

      final fluxforgeTable = TableInstance();
      fluxforgeTable.fields['setRtpc'] = (List<Object?> args) {
        rtpcId = args[0] as String?;
        rtpcValue = (args[1] as num?)?.toDouble();
        return null;
      };

      final env = LuaEnv(variables: {'fluxforge': fluxforgeTable});
      parse('fluxforge.setRtpc("Win_Intensity", 0.85)').evaluate(env: env);

      expect(rtpcId, equals('Win_Intensity'));
      expect(rtpcValue, closeTo(0.85, 0.001));
    });
  });

  group('Lua VM — error handling', () {
    test('syntax error throws', () {
      expect(
        () => parse('if then end'),
        throwsA(anything),
      );
    });

    test('undefined variable throws', () {
      expect(
        () => parse('return undefinedVar').evaluate(),
        throwsA(anything),
      );
    });

    test('calling non-function throws', () {
      final env = LuaEnv(variables: {'x': 42});
      expect(
        () => parse('x()').evaluate(env: env),
        throwsA(anything),
      );
    });
  });

  group('Lua VM — stdlib math', () {
    test('math.floor', () {
      final env = LuaEnv.withStdlib();
      final result = parse('return math.floor(3.7)').evaluate(env: env);
      expect(result, equals(3));
    });

    test('math.max', () {
      final env = LuaEnv.withStdlib();
      final result = parse('return math.max(5, 9, 2)').evaluate(env: env);
      expect(result, equals(9));
    });

    test('math.abs', () {
      final env = LuaEnv.withStdlib();
      final result = parse('return math.abs(-7)').evaluate(env: env);
      expect(result, equals(7));
    });
  });
}
