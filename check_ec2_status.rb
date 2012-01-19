#!/usr/bin/env ruby
require 'cgi'
require 'base64'
require 'net/https'
require 'openssl'
require 'rexml/document' 

ACCESS_KEY_ID = SOMETHING
SECRET_ACCESS_KEY = SOMETHING

Net::HTTP.version_1_2

NAGIOS_CODE_OK = 0
NAGIOS_CODE_WARNING = 1
NAGIOS_CODE_CRITICAL = 2
NAGIOS_CODE_UNKNOWN = 3

unless ARGV.length == 1
  puts "please pass the region name as arg"
  exit NAGIOS_CODE_UNKNOWN
end

END_POINT = "ec2.#{ARGV[0]}.amazonaws.com"

class EC2Client
  API_VERSION = '2011-12-15'
  SIGNATURE_VERSION = 2

  def initialize(accessKeyId, secretAccessKey, endpoint, algorithm = :SHA256)
    @accessKeyId = accessKeyId
    @secretAccessKey = secretAccessKey
    @endpoint = endpoint
    @algorithm = algorithm
  end

  def query(action, params = {})
    params = {
      :Action           => action,
      :Version          => API_VERSION,
      :Timestamp        => Time.now.getutc.strftime('%Y-%m-%dT%H:%M:%SZ'),
      :SignatureVersion => SIGNATURE_VERSION,
      :SignatureMethod  => "Hmac#{@algorithm}",
      :AWSAccessKeyId   => @accessKeyId,
    }.merge(params)

    signature = aws_sign(params)
    params[:Signature] = signature

    https = Net::HTTP.new(@endpoint, 443)
    https.use_ssl = true
    https.verify_mode = OpenSSL::SSL::VERIFY_NONE

    https.start do |w|
      req = Net::HTTP::Post.new('/',
        'Host' => @endpoint,
        'Content-Type' => 'application/x-www-form-urlencoded'
      )

      req.set_form_data(params)
      res = w.request(req)

      res.body
    end
  end

  private
  def aws_sign(params)
    params = params.sort_by {|a, b| a.to_s }.map {|k, v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.join('&')
    string_to_sign = "POST\n#{@endpoint}\n/\n#{params}"
    digest = OpenSSL::HMAC.digest(OpenSSL::Digest.const_get(@algorithm).new, @secretAccessKey, string_to_sign)
    Base64.encode64(digest).gsub("\n", '')
  end
end

begin
  ec2cli = EC2Client.new(ACCESS_KEY_ID, SECRET_ACCESS_KEY, END_POINT)
  source = ec2cli.query('DescribeInstanceStatus')
  doc = REXML::Document.new(source)
rescue => e
  puts "Error connecting to #{END_POINT} *** #{e}"
  exit NAGIOS_CODE_CRITICAL
end

errors = []

doc.each_element('Response/Errors/Error') do |error|
  errors << "#{error.text('Code')}:#{error.text('Message')}"
end

server_count = 0

doc.each_element('/DescribeInstanceStatusResponse/instanceStatusSet/item') do |item|
  server_count += 1
  instance_id = item.text('instanceId')
  az = item.text('availabilityZone')
  %w[systemStatus instanceStatus].each do |status_type|
    unless item.text("#{status_type}/status") == 'ok'
      item.each_element("#{status_type}/details/item") do |check|
        name = check.text('name')
        status = check.text('status')
        errors << "#{az}:#{instance_id}:#{name}-#{status}" 
      end
    end
  end
  
  eventsSet = item.elements['eventsSet']
  unless eventsSet.nil? 
    eventsSet.each_element('item') do |i|
      code = i.text('code')
      description = i.text('description')
    errors << "{az}:#{instance_id}:#{code}:#{description}"
    end
  end
end

unless errors.empty?
  puts errors.join(', ')
  exit NAGIOS_CODE_CRITICAL
end

puts "OK - #{server_count} healthy servers"
exit NAGIOS_CODE_OK