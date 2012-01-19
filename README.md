Few Nagios Plugins
==================

check_ec2_status
----------------
called with the region name as only argument, use the Instance Status Checks (see [the amazon blog](http://aws.typepad.com/aws/2012/01/ec2-instance-status-checks.html).
Will warn if the API fails, any machines dont pass the tests or if any machines are scheduled for reboot or retirement