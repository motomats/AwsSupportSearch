#!/usr/bin/env ruby
require 'aws-sdk-core'
require 'pp'
require 'json'
require 'time'
require 'logger'
log = Logger.new(STDERR)
log.level = Logger::WARN

accounts=["965789077213","self"]
languages=["en","ja"]
bucket="support-case-backup"

Aws.config[:region] = 'us-east-1'
s3 = Aws::S3::Client.new

cases=[]
accounts.each do |account|
  if account == 'self'
    iam = Aws::IAM::Client.new
    begin
      resp=iam.get_user
      account_id=resp.user.arn.match(/(\d){12}/)[0]
    rescue Aws::IAM::Erros::ServiceError
      log.warn "IAM.GetUser failed."
      next
    end
  else
    sts = Aws::STS::Client.new
    begin
      session=sts.assume_role(role_arn:"arn:aws:iam::#{account}:role/support",role_session_name:"support")
    rescue Aws::STS::Errors::ServiceError
      log.warn "AssumeRole for #{account} failed."
      next
    end
    account_id=account
  end

  support=(session)? Aws::Support::Client.new(
    access_key_id:session.credentials.access_key_id,
    secret_access_key:session.credentials.secret_access_key,
    session_token:session.credentials.session_token
  ) : Aws::Support::Client.new

  languages.each do |lang|
    begin
      support.describe_cases(
        include_resolved_cases: true,
        language: lang,
        include_communications: false,
        after_time: (Time.now-365*24*60*60).iso8601
      ).map{|page| page.cases}.flatten.each do |c|
        output=c.to_hash
        output[:account_id]=account_id
        output[:case_url]="https://aws.amazon.com/support/case?caseId=#{c.display_id}&language=#{lang}"
        case_body=""
        begin
          comms=support.describe_communications(
            case_id: c.case_id
          ).map{|page| page.communications}.flatten.reverse
          .select {|comm| comm.submitted_by != "Amazon Web Services <no-reply-aws@amazon.com>"}
          output[:last_updated]=comms.map {|comm| comm.time_created}.max
          comms.each do |comm|
            case_body+="--- "+comm.submitted_by+"\n"+comm.body if comm.body != ""
          end
        rescue Aws::Support::Errors::ServiceError => evar
          log.warn "communications were lost."
        end
        if case_body != ""
          output[:case_body]=case_body
          $stderr.puts JSON.pretty_generate(output)
          cases.push output
          begin Aws::S3::Errors::ServiceError
            resp=s3.put_object(
              body: JSON.pretty_generate(output),
              bucket: bucket,
              key: c.display_id+".json"
            )
            log.info resp
          rescue  Aws::S3::Errors::ServiceError => evar
            pp evar
            log.warn "s3.put_object failed"
          end
        end
      end
    rescue Aws::Support::Errors::ServiceError => evar
      log.warn evar.to_s
    end
  end
end

puts cases.map{ |c| {:id => c[:display_id], :type => "add", :fields => c } }.to_json
