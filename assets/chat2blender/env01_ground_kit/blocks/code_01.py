for socket in node.inputs:
    identifier = getattr(socket, "identifier", "")
    if identifier in identifiers:
        return socket

for socket in node.inputs:
    identifier = str(getattr(socket, "identifier", "")).lower()
    for wanted in identifiers:
        if identifier == str(wanted).lower():
            return socket

for socket in node.inputs:
    name = str(getattr(socket, "name", ""))
    if name in fallback_names:
        return socket

for socket in node.inputs:
    name = str(getattr(socket, "name", "")).lower()
    for wanted in fallback_names:
        if name == str(wanted).lower():
            return socket

raise RuntimeError(
    "ENV-01: required shader socket not found. "
    f"Identifiers={identifiers}, fallback_names={fallback_names}"
)