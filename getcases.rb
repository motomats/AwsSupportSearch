#!/usr/bin/env ruby
require 'aws-sdk-core'
require 'pp'

accounts=["111111111111","965789077213","self"]
languages=["en","ja"]

Aws.config[:region] = 'us-east-1'

accounts.each do |account|
  if account != 'self'
    sts = Aws::STS::Client.new
    begin
      session=sts.assume_role(role_arn:"arn:aws:iam::#{account}:role/support",role_session_name:"support")
    rescue Aws::STS::Errors::ServiceError
      puts "ERROR: AssumeRole for #{account} failed."
      next
    end
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
        include_communications: false
      ).map{|page| page.cases}.flatten.each do |c|
        case_id=c.case_id
        display_id=c.display_id
        case_body="https://aws.amazon.com/support/case?caseId=#{display_id}&language=#{lang}\n"
        begin
          support.describe_communications(
            case_id: case_id
          ).map{|page| page.communications}.flatten.reverse
          .select {|comm| comm.submitted_by != "Amazon Web Services <no-reply-aws@amazon.com>"}
          .each do |comm|
            pp comm
            case_body+="--- "+comm.submitted_by+"\n"+comm.body
          end
        rescue Aws::Support::Errors::ServiceError => evar
          puts "INFO: communications were lost."
        end
        puts case_body
      end
    rescue Aws::Support::Errors::ServiceError => evar
      pp evar
    end
  end
end
