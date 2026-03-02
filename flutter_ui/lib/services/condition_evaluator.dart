/// P-DSF Condition Evaluator — Recursive Descent Expression Parser
///
/// Evaluates boolean expressions against runtime variables for stage flow
/// conditional routing (gate nodes, enter/skip/exit conditions).
///
/// Supported operators:
///   Comparison: ==, !=, >, <, >=, <=
///   Logical:    &&, ||, !
///   Arithmetic: +, -, *, / (in sub-expressions)
///   Grouping:   ( )
///
/// Examples:
///   "win_amount > 0"
///   "scatter_count >= 3 && !turbo_mode"
///   "win_ratio >= 20.0 || jackpot_level != 'none'"
///   "(is_free_spin || is_cascade) && win_amount > 50"
///
/// NOT supported (by design — deterministic only):
///   Function calls, array ops, string manipulation, random, external API
library;

import '../models/stage_flow_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// TOKEN
// ═══════════════════════════════════════════════════════════════════════════

enum _TokenType {
  number,
  string,
  boolean,
  identifier,
  // Comparison
  eq, // ==
  ne, // !=
  gt, // >
  lt, // <
  gte, // >=
  lte, // <=
  // Logical
  and, // &&
  or, // ||
  not, // !
  // Arithmetic
  plus,
  minus,
  star,
  slash,
  // Grouping
  lparen,
  rparen,
  // End
  eof,
}

class _Token {
  final _TokenType type;
  final dynamic value;
  final int position;

  const _Token(this.type, this.value, this.position);

  @override
  String toString() => 'Token($type, $value @$position)';
}

// ═══════════════════════════════════════════════════════════════════════════
// TOKENIZER
// ═══════════════════════════════════════════════════════════════════════════

class _Tokenizer {
  final String source;
  int _pos = 0;

  _Tokenizer(this.source);

  List<_Token> tokenize() {
    final tokens = <_Token>[];
    while (_pos < source.length) {
      _skipWhitespace();
      if (_pos >= source.length) break;

      final start = _pos;
      final c = source[_pos];

      // Two-char operators
      if (_pos + 1 < source.length) {
        final two = source.substring(_pos, _pos + 2);
        switch (two) {
          case '==':
            tokens.add(_Token(_TokenType.eq, '==', start));
            _pos += 2;
            continue;
          case '!=':
            tokens.add(_Token(_TokenType.ne, '!=', start));
            _pos += 2;
            continue;
          case '>=':
            tokens.add(_Token(_TokenType.gte, '>=', start));
            _pos += 2;
            continue;
          case '<=':
            tokens.add(_Token(_TokenType.lte, '<=', start));
            _pos += 2;
            continue;
          case '&&':
            tokens.add(_Token(_TokenType.and, '&&', start));
            _pos += 2;
            continue;
          case '||':
            tokens.add(_Token(_TokenType.or, '||', start));
            _pos += 2;
            continue;
        }
      }

      // Single-char operators
      switch (c) {
        case '>':
          tokens.add(_Token(_TokenType.gt, '>', start));
          _pos++;
          continue;
        case '<':
          tokens.add(_Token(_TokenType.lt, '<', start));
          _pos++;
          continue;
        case '!':
          tokens.add(_Token(_TokenType.not, '!', start));
          _pos++;
          continue;
        case '+':
          tokens.add(_Token(_TokenType.plus, '+', start));
          _pos++;
          continue;
        case '-':
          // Negative number check: minus followed by digit, and previous token is
          // an operator or start
          if (_pos + 1 < source.length &&
              _isDigit(source[_pos + 1]) &&
              (tokens.isEmpty || _isOperatorToken(tokens.last.type))) {
            tokens.add(_readNumber());
            continue;
          }
          tokens.add(_Token(_TokenType.minus, '-', start));
          _pos++;
          continue;
        case '*':
          tokens.add(_Token(_TokenType.star, '*', start));
          _pos++;
          continue;
        case '/':
          tokens.add(_Token(_TokenType.slash, '/', start));
          _pos++;
          continue;
        case '(':
          tokens.add(_Token(_TokenType.lparen, '(', start));
          _pos++;
          continue;
        case ')':
          tokens.add(_Token(_TokenType.rparen, ')', start));
          _pos++;
          continue;
      }

      // String literals
      if (c == "'" || c == '"') {
        tokens.add(_readString());
        continue;
      }

      // Numbers
      if (_isDigit(c)) {
        tokens.add(_readNumber());
        continue;
      }

      // Identifiers and keywords
      if (_isIdentStart(c)) {
        tokens.add(_readIdentifier());
        continue;
      }

      throw FormatException('Unexpected character "$c" at position $start');
    }

    tokens.add(_Token(_TokenType.eof, null, _pos));
    return tokens;
  }

  void _skipWhitespace() {
    while (_pos < source.length && source[_pos] == ' ') {
      _pos++;
    }
  }

  _Token _readNumber() {
    final start = _pos;
    if (_pos < source.length && source[_pos] == '-') _pos++;

    while (_pos < source.length && _isDigit(source[_pos])) {
      _pos++;
    }

    // Decimal part
    if (_pos < source.length && source[_pos] == '.' && _pos + 1 < source.length && _isDigit(source[_pos + 1])) {
      _pos++;
      while (_pos < source.length && _isDigit(source[_pos])) {
        _pos++;
      }
      return _Token(
          _TokenType.number, double.parse(source.substring(start, _pos)), start);
    }

    final intStr = source.substring(start, _pos);
    final asInt = int.tryParse(intStr);
    if (asInt != null) {
      return _Token(_TokenType.number, asInt, start);
    }
    return _Token(_TokenType.number, double.parse(intStr), start);
  }

  _Token _readString() {
    final quote = source[_pos];
    final start = _pos;
    _pos++; // skip opening quote
    final buf = StringBuffer();
    while (_pos < source.length && source[_pos] != quote) {
      if (source[_pos] == '\\' && _pos + 1 < source.length) {
        _pos++;
      }
      buf.write(source[_pos]);
      _pos++;
    }
    if (_pos < source.length) _pos++; // skip closing quote
    return _Token(_TokenType.string, buf.toString(), start);
  }

  _Token _readIdentifier() {
    final start = _pos;
    while (_pos < source.length && _isIdentChar(source[_pos])) {
      _pos++;
    }
    final text = source.substring(start, _pos);

    // Keywords
    if (text == 'true') return _Token(_TokenType.boolean, true, start);
    if (text == 'false') return _Token(_TokenType.boolean, false, start);

    return _Token(_TokenType.identifier, text, start);
  }

  bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  bool _isIdentStart(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        c == '_';
  }

  bool _isIdentChar(String c) => _isIdentStart(c) || _isDigit(c);

  bool _isOperatorToken(_TokenType type) {
    return type == _TokenType.eq ||
        type == _TokenType.ne ||
        type == _TokenType.gt ||
        type == _TokenType.lt ||
        type == _TokenType.gte ||
        type == _TokenType.lte ||
        type == _TokenType.and ||
        type == _TokenType.or ||
        type == _TokenType.not ||
        type == _TokenType.plus ||
        type == _TokenType.minus ||
        type == _TokenType.star ||
        type == _TokenType.slash ||
        type == _TokenType.lparen;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PARSER + EVALUATOR (Recursive Descent)
// ═══════════════════════════════════════════════════════════════════════════

/// Evaluates boolean expressions against runtime variable maps.
///
/// Grammar (precedence low → high):
///   expr       → or_expr
///   or_expr    → and_expr ( '||' and_expr )*
///   and_expr   → not_expr ( '&&' not_expr )*
///   not_expr   → '!' not_expr | compare
///   compare    → additive ( ('==' | '!=' | '>' | '<' | '>=' | '<=') additive )?
///   additive   → multiplicative ( ('+' | '-') multiplicative )*
///   multiplicative → unary ( ('*' | '/') unary )*
///   unary      → '-' unary | primary
///   primary    → NUMBER | STRING | BOOL | IDENTIFIER | '(' expr ')'
class ConditionEvaluator {
  /// Parse and evaluate an expression against variables.
  /// Returns null if expression is null or empty (treated as "always true").
  bool? evaluate(String? expression, Map<String, dynamic> variables) {
    if (expression == null || expression.trim().isEmpty) return null;

    final tokens = _Tokenizer(expression).tokenize();
    final parser = _Parser(tokens, variables);
    final result = parser.parseExpression();
    return _toBool(result);
  }

  /// Validate an expression without evaluating it.
  /// Returns list of errors (empty = valid).
  List<String> validate(
    String expression,
    Map<String, RuntimeVariableDefinition> schema,
  ) {
    final errors = <String>[];

    try {
      final tokens = _Tokenizer(expression).tokenize();
      // Check for unknown variables
      final varNames = schema.keys.toSet();
      for (final token in tokens) {
        if (token.type == _TokenType.identifier) {
          final name = token.value as String;
          if (!varNames.contains(name)) {
            errors.add('Unknown variable "$name" at position ${token.position}');
          }
        }
      }

      // Try parsing to catch syntax errors
      final dummyVars = <String, dynamic>{};
      for (final entry in schema.entries) {
        dummyVars[entry.key] = entry.value.defaultValue ?? 0;
      }
      final parser = _Parser(tokens, dummyVars);
      parser.parseExpression();
      if (parser._currentToken.type != _TokenType.eof) {
        errors.add(
            'Unexpected token "${parser._currentToken.value}" at position ${parser._currentToken.position}');
      }
    } on FormatException catch (e) {
      errors.add(e.message);
    }

    return errors;
  }

  /// Extract all variable names referenced in an expression.
  Set<String> extractVariables(String expression) {
    final vars = <String>{};
    try {
      final tokens = _Tokenizer(expression).tokenize();
      for (final token in tokens) {
        if (token.type == _TokenType.identifier) {
          vars.add(token.value as String);
        }
      }
    } on FormatException {
      // Ignore — best effort extraction
    }
    return vars;
  }
}

class _Parser {
  final List<_Token> _tokens;
  final Map<String, dynamic> _variables;
  int _index = 0;

  _Parser(this._tokens, this._variables);

  _Token get _currentToken => _tokens[_index];

  _Token _advance() {
    final token = _tokens[_index];
    if (_index < _tokens.length - 1) _index++;
    return token;
  }

  bool _match(_TokenType type) {
    if (_currentToken.type == type) {
      _advance();
      return true;
    }
    return false;
  }

  dynamic parseExpression() => _parseOr();

  dynamic _parseOr() {
    var left = _parseAnd();
    while (_currentToken.type == _TokenType.or) {
      _advance();
      final right = _parseAnd();
      left = _toBool(left) || _toBool(right);
    }
    return left;
  }

  dynamic _parseAnd() {
    var left = _parseNot();
    while (_currentToken.type == _TokenType.and) {
      _advance();
      final right = _parseNot();
      left = _toBool(left) && _toBool(right);
    }
    return left;
  }

  dynamic _parseNot() {
    if (_match(_TokenType.not)) {
      final expr = _parseNot();
      return !_toBool(expr);
    }
    return _parseComparison();
  }

  dynamic _parseComparison() {
    final left = _parseAdditive();

    switch (_currentToken.type) {
      case _TokenType.eq:
        _advance();
        final right = _parseAdditive();
        return _compareEq(left, right);
      case _TokenType.ne:
        _advance();
        final right = _parseAdditive();
        return !_compareEq(left, right);
      case _TokenType.gt:
        _advance();
        final right = _parseAdditive();
        return _toNum(left) > _toNum(right);
      case _TokenType.lt:
        _advance();
        final right = _parseAdditive();
        return _toNum(left) < _toNum(right);
      case _TokenType.gte:
        _advance();
        final right = _parseAdditive();
        return _toNum(left) >= _toNum(right);
      case _TokenType.lte:
        _advance();
        final right = _parseAdditive();
        return _toNum(left) <= _toNum(right);
      default:
        return left;
    }
  }

  dynamic _parseAdditive() {
    var left = _parseMultiplicative();
    while (_currentToken.type == _TokenType.plus ||
        _currentToken.type == _TokenType.minus) {
      final op = _advance();
      final right = _parseMultiplicative();
      if (op.type == _TokenType.plus) {
        left = _toNum(left) + _toNum(right);
      } else {
        left = _toNum(left) - _toNum(right);
      }
    }
    return left;
  }

  dynamic _parseMultiplicative() {
    var left = _parseUnary();
    while (_currentToken.type == _TokenType.star ||
        _currentToken.type == _TokenType.slash) {
      final op = _advance();
      final right = _parseUnary();
      if (op.type == _TokenType.star) {
        left = _toNum(left) * _toNum(right);
      } else {
        final divisor = _toNum(right);
        left = divisor == 0 ? 0.0 : _toNum(left) / divisor;
      }
    }
    return left;
  }

  dynamic _parseUnary() {
    if (_match(_TokenType.minus)) {
      final expr = _parseUnary();
      return -_toNum(expr);
    }
    return _parsePrimary();
  }

  dynamic _parsePrimary() {
    final token = _currentToken;

    switch (token.type) {
      case _TokenType.number:
        _advance();
        return token.value;
      case _TokenType.string:
        _advance();
        return token.value;
      case _TokenType.boolean:
        _advance();
        return token.value;
      case _TokenType.identifier:
        _advance();
        final name = token.value as String;
        if (_variables.containsKey(name)) {
          return _variables[name];
        }
        return null;
      case _TokenType.lparen:
        _advance();
        final result = parseExpression();
        if (_currentToken.type == _TokenType.rparen) {
          _advance();
        }
        return result;
      default:
        throw FormatException(
            'Unexpected token "${token.value}" at position ${token.position}');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

bool _toBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return value.isNotEmpty && value != 'false' && value != 'none';
  return false;
}

double _toNum(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  if (value is bool) return value ? 1 : 0;
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

bool _compareEq(dynamic a, dynamic b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  // Numeric comparison with type coercion
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  // String comparison
  return a.toString() == b.toString();
}
