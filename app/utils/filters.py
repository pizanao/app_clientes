def format_currency(value):
    """Formats float/decimal into Brazilian Real (R$ X.XXX,XX)."""
    if value is None:
        return "R$ 0,00"
    try:
        val = float(value)
        return f"R$ {val:,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.')
    except (ValueError, TypeError):
        return str(value)


def format_date(value, fmt='%d/%m/%Y %H:%M'):
    """Formats datetime object to standard Brazilian date format."""
    if not value:
        return "-"
    try:
        return value.strftime(fmt)
    except Exception:
        return str(value)


def format_date_short(value):
    """Formats datetime object to short DD/MM/YYYY."""
    return format_date(value, fmt='%d/%m/%Y')


def format_document(doc):
    """Formats CPF (11 digits) or CNPJ (14 digits) if digits only."""
    if not doc:
        return "-"
    digits = ''.join(filter(str.isdigit, str(doc)))
    if len(digits) == 11:
        return f"{digits[:3]}.{digits[3:6]}.{digits[6:9]}-{digits[9:]}"
    elif len(digits) == 14:
        return f"{digits[:2]}.{digits[2:5]}.{digits[5:8]}/{digits[8:12]}-{digits[12:]}"
    return doc


def format_phone(phone):
    """Formats Brazilian phone numbers."""
    if not phone:
        return "-"
    digits = ''.join(filter(str.isdigit, str(phone)))
    if len(digits) == 11:
        return f"({digits[:2]}) {digits[2:7]}-{digits[7:]}"
    elif len(digits) == 10:
        return f"({digits[:2]}) {digits[2:6]}-{digits[6:]}"
    return phone


def init_filters(app):
    app.jinja_env.filters['currency'] = format_currency
    app.jinja_env.filters['datetime_br'] = format_date
    app.jinja_env.filters['date_br'] = format_date_short
    app.jinja_env.filters['doc_br'] = format_document
    app.jinja_env.filters['phone_br'] = format_phone
