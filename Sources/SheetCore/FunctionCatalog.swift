import Foundation

public enum FunctionCategory: String, CaseIterable, Sendable {
    case math = "Math & Trig"
    case statistical = "Statistical"
    case logical = "Logical"
    case text = "Text"
    case lookup = "Lookup & Reference"
    case dateTime = "Date & Time"
    case financial = "Financial"
    case information = "Information"
}

public struct FunctionInfo: Sendable, Identifiable {
    public let name: String
    public let signature: String
    public let summary: String
    public let category: FunctionCategory

    public var id: String { name }
}

/// Every function the calculator implements, for menus, autocomplete and argument hints.
public enum FunctionCatalog {
    public static let all: [FunctionInfo] = entries
        .map { FunctionInfo(name: $0.0, signature: $0.1, summary: $0.2, category: $0.3) }
        .sorted { $0.name < $1.name }

    public static func info(_ name: String) -> FunctionInfo? {
        let upper = name.uppercased()
        return all.first { $0.name == upper }
    }

    public static func matching(prefix: String) -> [FunctionInfo] {
        let upper = prefix.uppercased()
        return all.filter { $0.name.hasPrefix(upper) }
    }

    private static let entries: [(String, String, String, FunctionCategory)] = [
        ("ABS", "ABS(number)", "Absolute value of a number.", .math),
        ("CEILING", "CEILING(number, [significance])", "Rounds up to a multiple of significance.", .math),
        ("EXP", "EXP(number)", "e raised to a power.", .math),
        ("FLOOR", "FLOOR(number, [significance])", "Rounds down to a multiple of significance.", .math),
        ("INT", "INT(number)", "Rounds down to the nearest integer.", .math),
        ("LN", "LN(number)", "Natural logarithm.", .math),
        ("LOG10", "LOG10(number)", "Base-10 logarithm.", .math),
        ("MOD", "MOD(number, divisor)", "Remainder after division.", .math),
        ("PI", "PI()", "The value of pi.", .math),
        ("POWER", "POWER(number, power)", "A number raised to a power.", .math),
        ("PRODUCT", "PRODUCT(number1, [number2], …)", "Multiplies numbers.", .math),
        ("RAND", "RAND()", "Random number between 0 and 1.", .math),
        ("RANDBETWEEN", "RANDBETWEEN(bottom, top)", "Random integer between two numbers.", .math),
        ("ROUND", "ROUND(number, num_digits)", "Rounds to a number of digits.", .math),
        ("ROUNDDOWN", "ROUNDDOWN(number, num_digits)", "Rounds toward zero.", .math),
        ("ROUNDUP", "ROUNDUP(number, num_digits)", "Rounds away from zero.", .math),
        ("SIGN", "SIGN(number)", "1, 0 or -1 depending on the sign.", .math),
        ("SQRT", "SQRT(number)", "Square root.", .math),
        ("SUM", "SUM(number1, [number2], …)", "Adds numbers.", .math),
        ("SUMIF", "SUMIF(range, criteria, [sum_range])", "Adds cells that meet a condition.", .math),
        ("SUMIFS", "SUMIFS(sum_range, criteria_range1, criteria1, …)", "Adds cells that meet several conditions.", .math),
        ("SUMPRODUCT", "SUMPRODUCT(array1, [array2], …)", "Sum of the products of matching cells.", .math),

        ("AVERAGE", "AVERAGE(number1, [number2], …)", "Arithmetic mean.", .statistical),
        ("AVERAGEIF", "AVERAGEIF(range, criteria, [average_range])", "Mean of cells that meet a condition.", .statistical),
        ("AVERAGEIFS", "AVERAGEIFS(average_range, criteria_range1, criteria1, …)", "Mean of cells that meet several conditions.", .statistical),
        ("COUNT", "COUNT(value1, [value2], …)", "Counts numbers.", .statistical),
        ("COUNTA", "COUNTA(value1, [value2], …)", "Counts non-empty cells.", .statistical),
        ("COUNTBLANK", "COUNTBLANK(range)", "Counts empty cells.", .statistical),
        ("COUNTIF", "COUNTIF(range, criteria)", "Counts cells that meet a condition.", .statistical),
        ("COUNTIFS", "COUNTIFS(criteria_range1, criteria1, …)", "Counts cells that meet several conditions.", .statistical),
        ("LARGE", "LARGE(array, k)", "The k-th largest value.", .statistical),
        ("MAX", "MAX(number1, [number2], …)", "Largest value.", .statistical),
        ("MAXIFS", "MAXIFS(max_range, criteria_range1, criteria1, …)", "Largest value that meets conditions.", .statistical),
        ("MEDIAN", "MEDIAN(number1, [number2], …)", "Middle value.", .statistical),
        ("MIN", "MIN(number1, [number2], …)", "Smallest value.", .statistical),
        ("MINIFS", "MINIFS(min_range, criteria_range1, criteria1, …)", "Smallest value that meets conditions.", .statistical),
        ("RANK", "RANK(number, ref, [order])", "Rank of a number in a list.", .statistical),
        ("RANK.EQ", "RANK.EQ(number, ref, [order])", "Rank of a number in a list.", .statistical),
        ("SMALL", "SMALL(array, k)", "The k-th smallest value.", .statistical),
        ("STDEV", "STDEV(number1, [number2], …)", "Sample standard deviation.", .statistical),
        ("STDEV.P", "STDEV.P(number1, [number2], …)", "Population standard deviation.", .statistical),
        ("STDEV.S", "STDEV.S(number1, [number2], …)", "Sample standard deviation.", .statistical),
        ("VAR", "VAR(number1, [number2], …)", "Sample variance.", .statistical),
        ("VAR.P", "VAR.P(number1, [number2], …)", "Population variance.", .statistical),
        ("VAR.S", "VAR.S(number1, [number2], …)", "Sample variance.", .statistical),

        ("AND", "AND(logical1, [logical2], …)", "TRUE if all arguments are TRUE.", .logical),
        ("FALSE", "FALSE()", "The value FALSE.", .logical),
        ("IF", "IF(logical_test, value_if_true, [value_if_false])", "Chooses a value by a condition.", .logical),
        ("IFERROR", "IFERROR(value, value_if_error)", "A fallback when a value is an error.", .logical),
        ("IFS", "IFS(test1, value1, [test2, value2], …)", "Value of the first true condition.", .logical),
        ("NOT", "NOT(logical)", "Reverses TRUE and FALSE.", .logical),
        ("OR", "OR(logical1, [logical2], …)", "TRUE if any argument is TRUE.", .logical),
        ("SWITCH", "SWITCH(expression, value1, result1, …, [default])", "Result matching a value.", .logical),
        ("TRUE", "TRUE()", "The value TRUE.", .logical),

        ("CHAR", "CHAR(number)", "Character for a code.", .text),
        ("CODE", "CODE(text)", "Code of the first character.", .text),
        ("CONCAT", "CONCAT(text1, [text2], …)", "Joins text, including ranges.", .text),
        ("CONCATENATE", "CONCATENATE(text1, [text2], …)", "Joins text.", .text),
        ("EXACT", "EXACT(text1, text2)", "TRUE if texts match exactly.", .text),
        ("FIND", "FIND(find_text, within_text, [start_num])", "Position of text, case-sensitive.", .text),
        ("LEFT", "LEFT(text, [num_chars])", "Characters from the start.", .text),
        ("LEN", "LEN(text)", "Number of characters.", .text),
        ("LOWER", "LOWER(text)", "Converts to lowercase.", .text),
        ("MID", "MID(text, start_num, num_chars)", "Characters from the middle.", .text),
        ("PROPER", "PROPER(text)", "Capitalizes each word.", .text),
        ("REPLACE", "REPLACE(old_text, start_num, num_chars, new_text)", "Replaces characters by position.", .text),
        ("REPT", "REPT(text, number_times)", "Repeats text.", .text),
        ("RIGHT", "RIGHT(text, [num_chars])", "Characters from the end.", .text),
        ("SEARCH", "SEARCH(find_text, within_text, [start_num])", "Position of text, ignoring case.", .text),
        ("SUBSTITUTE", "SUBSTITUTE(text, old_text, new_text, [instance_num])", "Replaces matching text.", .text),
        ("TEXT", "TEXT(value, format_text)", "Formats a number as text.", .text),
        ("TEXTJOIN", "TEXTJOIN(delimiter, ignore_empty, text1, …)", "Joins text with a delimiter.", .text),
        ("TRIM", "TRIM(text)", "Removes extra spaces.", .text),
        ("UPPER", "UPPER(text)", "Converts to uppercase.", .text),
        ("VALUE", "VALUE(text)", "Converts text to a number.", .text),

        ("CHOOSE", "CHOOSE(index_num, value1, [value2], …)", "Picks a value by position.", .lookup),
        ("COLUMN", "COLUMN([reference])", "Column number of a reference.", .lookup),
        ("COLUMNS", "COLUMNS(array)", "Number of columns.", .lookup),
        ("HLOOKUP", "HLOOKUP(lookup_value, table_array, row_index_num, [range_lookup])", "Looks up across the top row.", .lookup),
        ("INDEX", "INDEX(array, row_num, [column_num])", "Value at a position in a range.", .lookup),
        ("MATCH", "MATCH(lookup_value, lookup_array, [match_type])", "Position of a value in a range.", .lookup),
        ("ROW", "ROW([reference])", "Row number of a reference.", .lookup),
        ("ROWS", "ROWS(array)", "Number of rows.", .lookup),
        ("VLOOKUP", "VLOOKUP(lookup_value, table_array, col_index_num, [range_lookup])", "Looks up down the first column.", .lookup),
        ("XLOOKUP", "XLOOKUP(lookup_value, lookup_array, return_array, [if_not_found])", "Exact lookup in any direction.", .lookup),

        ("DATE", "DATE(year, month, day)", "Serial number of a date.", .dateTime),
        ("DAY", "DAY(serial_number)", "Day of the month.", .dateTime),
        ("DAYS", "DAYS(end_date, start_date)", "Days between two dates.", .dateTime),
        ("EDATE", "EDATE(start_date, months)", "Date a number of months away.", .dateTime),
        ("EOMONTH", "EOMONTH(start_date, months)", "Last day of a month.", .dateTime),
        ("MONTH", "MONTH(serial_number)", "Month of a date.", .dateTime),
        ("NOW", "NOW()", "Current date and time.", .dateTime),
        ("TODAY", "TODAY()", "Current date.", .dateTime),
        ("WEEKDAY", "WEEKDAY(serial_number, [return_type])", "Day of the week.", .dateTime),
        ("YEAR", "YEAR(serial_number)", "Year of a date.", .dateTime),

        ("ACOS", "ACOS(number)", "Arccosine in radians.", .math),
        ("ASIN", "ASIN(number)", "Arcsine in radians.", .math),
        ("ATAN", "ATAN(number)", "Arctangent in radians.", .math),
        ("ATAN2", "ATAN2(x_num, y_num)", "Arctangent of x and y coordinates.", .math),
        ("BIN2DEC", "BIN2DEC(number)", "Binary to decimal.", .math),
        ("COS", "COS(number)", "Cosine of an angle in radians.", .math),
        ("COSH", "COSH(number)", "Hyperbolic cosine.", .math),
        ("DEC2BIN", "DEC2BIN(number, [places])", "Decimal to binary.", .math),
        ("DEC2HEX", "DEC2HEX(number, [places])", "Decimal to hexadecimal.", .math),
        ("DEC2OCT", "DEC2OCT(number, [places])", "Decimal to octal.", .math),
        ("DEGREES", "DEGREES(angle)", "Radians to degrees.", .math),
        ("EVEN", "EVEN(number)", "Rounds up to an even integer.", .math),
        ("FACT", "FACT(number)", "Factorial.", .math),
        ("GCD", "GCD(number1, [number2], …)", "Greatest common divisor.", .math),
        ("HEX2DEC", "HEX2DEC(number)", "Hexadecimal to decimal.", .math),
        ("LCM", "LCM(number1, [number2], …)", "Least common multiple.", .math),
        ("LOG", "LOG(number, [base])", "Logarithm to a base.", .math),
        ("MROUND", "MROUND(number, multiple)", "Rounds to the nearest multiple.", .math),
        ("OCT2DEC", "OCT2DEC(number)", "Octal to decimal.", .math),
        ("ODD", "ODD(number)", "Rounds up to an odd integer.", .math),
        ("QUOTIENT", "QUOTIENT(numerator, denominator)", "Integer part of a division.", .math),
        ("RADIANS", "RADIANS(angle)", "Degrees to radians.", .math),
        ("SIN", "SIN(number)", "Sine of an angle in radians.", .math),
        ("SINH", "SINH(number)", "Hyperbolic sine.", .math),
        ("SUBTOTAL", "SUBTOTAL(function_num, ref1, …)", "Subtotal that skips filtered rows.", .math),
        ("SUMSQ", "SUMSQ(number1, [number2], …)", "Sum of squares.", .math),
        ("TAN", "TAN(number)", "Tangent of an angle in radians.", .math),
        ("TANH", "TANH(number)", "Hyperbolic tangent.", .math),
        ("TRUNC", "TRUNC(number, [num_digits])", "Truncates to a number of digits.", .math),
        ("AVERAGEA", "AVERAGEA(value1, [value2], …)", "Mean counting text as 0 and TRUE as 1.", .statistical),
        ("MAXA", "MAXA(value1, [value2], …)", "Largest value, counting text and logicals.", .statistical),
        ("MINA", "MINA(value1, [value2], …)", "Smallest value, counting text and logicals.", .statistical),
        ("MODE", "MODE(number1, [number2], …)", "Most frequent value.", .statistical),
        ("MODE.SNGL", "MODE.SNGL(number1, [number2], …)", "Most frequent value.", .statistical),
        ("STDEVP", "STDEVP(number1, [number2], …)", "Population standard deviation.", .statistical),
        ("VARP", "VARP(number1, [number2], …)", "Population variance.", .statistical),
        ("CLEAN", "CLEAN(text)", "Removes non-printing characters.", .text),
        ("T", "T(value)", "Text, or empty text for other values.", .text),
        ("HYPERLINK", "HYPERLINK(link_location, [friendly_name])", "Shows a link's name.", .lookup),
        ("INDIRECT", "INDIRECT(ref_text)", "Reference named by text.", .lookup),
        ("LOOKUP", "LOOKUP(lookup_value, lookup_vector, [result_vector])", "Approximate lookup in sorted data.", .lookup),
        ("OFFSET", "OFFSET(reference, rows, cols, [height], [width])", "Reference moved from a starting cell.", .lookup),
        ("XMATCH", "XMATCH(lookup_value, lookup_array, [match_mode])", "Position of a value, exact or next.", .lookup),
        ("HOUR", "HOUR(serial_number)", "Hour of a time.", .dateTime),
        ("MINUTE", "MINUTE(serial_number)", "Minute of a time.", .dateTime),
        ("NETWORKDAYS", "NETWORKDAYS(start_date, end_date, [holidays])", "Working days between dates.", .dateTime),
        ("SECOND", "SECOND(serial_number)", "Second of a time.", .dateTime),
        ("TIME", "TIME(hour, minute, second)", "Serial number of a time.", .dateTime),
        ("WORKDAY", "WORKDAY(start_date, days, [holidays])", "Date a number of working days away.", .dateTime),
        ("FV", "FV(rate, nper, pmt, [pv], [type])", "Future value of an investment.", .financial),
        ("IRR", "IRR(values, [guess])", "Internal rate of return.", .financial),
        ("NPER", "NPER(rate, pmt, pv, [fv], [type])", "Number of payment periods.", .financial),
        ("NPV", "NPV(rate, value1, [value2], …)", "Net present value.", .financial),
        ("PMT", "PMT(rate, nper, pv, [fv], [type])", "Loan payment per period.", .financial),
        ("PV", "PV(rate, nper, pmt, [fv], [type])", "Present value of an investment.", .financial),
        ("RATE", "RATE(nper, pmt, pv, [fv], [type], [guess])", "Interest rate per period.", .financial),
        ("ISEVEN", "ISEVEN(number)", "TRUE for even numbers.", .information),
        ("ISNONTEXT", "ISNONTEXT(value)", "TRUE for anything but text.", .information),
        ("ISODD", "ISODD(number)", "TRUE for odd numbers.", .information),
        ("ISREF", "ISREF(value)", "TRUE for references.", .information),
        ("N", "N(value)", "A value converted to a number.", .information),
        ("ISBLANK", "ISBLANK(value)", "TRUE if a cell is empty.", .information),
        ("ISERROR", "ISERROR(value)", "TRUE for any error.", .information),
        ("ISLOGICAL", "ISLOGICAL(value)", "TRUE for TRUE or FALSE.", .information),
        ("ISNA", "ISNA(value)", "TRUE for #N/A.", .information),
        ("ISNUMBER", "ISNUMBER(value)", "TRUE for numbers.", .information),
        ("ISTEXT", "ISTEXT(value)", "TRUE for text.", .information),
        ("NA", "NA()", "The #N/A error.", .information),
    ]
}
