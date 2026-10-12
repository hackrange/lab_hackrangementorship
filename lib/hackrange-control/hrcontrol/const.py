"""Where everything is.

One copy of each path and port, because the panel, the launcher and the
installer all have to agree about them and three copies drift.

Author: Tim Rice - tim.j.rice@hackrange.com
"""

HR_ROOT = "/opt/hackrange-mentorship"
HR_ETC = "/etc/hackrange-mentorship"

CATALOG = HR_ROOT + "/config/labs.conf"
ANSWERS = HR_ROOT + "/config/answers"
LOGINS = HR_ROOT + "/config/lab-logins.conf"
ACCESS_ENV = HR_ETC + "/access.env"
STATE = HR_ETC + "/current-lab"

LAB_CONTAINER = "hackrange-mentorship-lab"
GUAC_CONTAINER = "hackrange-mentorship-guacamole"
GUAC_MAPPING = HR_ETC + "/guacamole/user-mapping.xml"
COMPANION_CONTAINER = "hackrange-mentorship-dast"

HACKRANGE_LAB = "/usr/local/bin/hackrange-lab"
HACKRANGE_CHECK = "/usr/local/bin/hackrange-check"

WEB_PORT = 8456
SSH_PORT = 2223
RDP_PORT = 13489
# What the lab session itself listens on, loopback only.  nginx and the web
# desktop reach the lab through these, so a lab is only usable once the one
# its protocol uses is answering.
SSH_INNER = 12223
RDP_INNER = 13490
GUAC_UPSTREAM = 18091   # what the web desktop itself listens on, loopback only

# The web desktop's connection is named this and nothing else.  Guacamole
# builds the address of a session from the connection's name, so a name that
# changed with the lab gave every lab a different address and broke a student's
# bookmark the moment they started a different one.
GUAC_CONNECTION = "Hackrange Mentorship Lab"
