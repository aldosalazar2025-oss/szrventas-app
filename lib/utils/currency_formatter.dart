import 'package:intl/intl.dart';

class CurrencyFormatter {
  static String format(double amount, String symbol) {
    final format = NumberFormat.currency(
      locale: 'en_US', // en_US always uses '.' for decimals and ',' for thousands
      symbol: symbol,
      customPattern: '\u00A4 #,##0.00', // ¤ represents the symbol. E.g. "S/ 1,500.00"
    );
    return format.format(amount);
  }
}
