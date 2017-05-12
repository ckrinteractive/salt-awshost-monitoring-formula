{% set aws_access_key_id = salt['pillar.get']('awshost-monitoring:aws_access_key_id', '') %}
{% set aws_secret_access_key = salt['pillar.get']('awshost-monitoring:aws_secret_access_key', '') %}
{% set server_id = salt['grains.get']('id', 'nameless') %}


/srv/cloudwatch-monitoring-scripts:
  file.recurse:
    - source: salt://awshost-monitoring/files/cloudwatch-monitoring-scripts
    - file_mode: '0755'

revert-python-pip-awshost:
  file.rename:
    # This state only to undo a previous work arond
    - name: /usr/local/lib/python2.7/dist-packages/requests
    - source: /usr/local/lib/python2.7/dist-packages/requests.toremove
  pkg.removed:
    - require:
      - file: revert-python-pip-awshost
    - name: python-pip

install-pip-awshost:
  require:
   - pkg: revert-python-pip-awshost
  cmd.run:
    - name: curl https://bootstrap.pypa.io/get-pip.py | python - 'pip==8.1.1'
    - unless: which pip

required-packages:
  require:
    - cmd: install-pip-awshost
  pkg.installed:
    - refresh: True
    - pkgs:
      - unzip
      - libwww-perl
      - libdatetime-perl
      - ntp

required-pip-packages-awshost:
  require:
    - cmd: install-pip-awshost
  pip.installed:
    - names:
      - urllib3[secure]
      - boto == 2.46.1


/srv/cloudwatch-monitoring-scripts/awscreds.conf:
  require:
    - cmd: /srv/cloudwatch-monitoring-scripts
  file.managed:
    - source: salt://awshost-monitoring/files/cloudwatch-monitoring-scripts/awscreds.template
    - template: jinja
    - context:
      aws_access_key_id: {{ aws_access_key_id }}
      aws_secret_key: {{ aws_secret_access_key }}


setup-cron:
  require:
    - cmd: /srv/cloudwatch-monitoring-scripts
    - cmd: /srv/cloudwatch-monitoring-scripts/awscreds.conf
    - cmd: required-packages
  cron.present:
    - name: /srv/cloudwatch-monitoring-scripts/mon-put-instance-data.pl --mem-util --disk-space-util --disk-path=/ --from-cron
    - user: root


sync-time:
  require:
    - cmd: required-packages
  cmd.run:
    - name: service ntp stop && ntpdate -s time.nist.gov && service ntp start
    - user: root


{% for name, alarm in salt['pillar.get']('awshost-monitoring:alarms', {}).iteritems() %}
{{ name }}:
  boto_cloudwatch_alarm.present:
    - name: {{ server_id }} - {{ name }}
    - keyid: {{ aws_access_key_id }}
    - key: {{ aws_secret_access_key }}
    - attributes:
        metric: {{ alarm.get('metric') }}
        namespace: {{ alarm.get('namespace', 'System/Linux') }}
        statistic: {{ alarm.get('statistic', 'Average') }}
        comparison: "{{ alarm.get('comparison', '>=') }}"
        threshold: {{ alarm.get('threshold', 75) }}
        period: {{ alarm.get('period', 300) }}
        evaluation_periods: 1
        dimensions:
          InstanceId: {{ salt['grains.get']('instance_meta:instance-id') }}
          {% for name, value in alarm.get('dimensions', {}).iteritems() -%}
            {{ name }}: {{ value }}
          {% endfor %}
        alarm_actions:
          {% for alarm_action in alarm.get('alarm_actions', salt['pillar.get']('awshost-monitoring:alarm_actions', [])) -%}
            - {{ alarm_action }}
          {% endfor %}
{% endfor %}
