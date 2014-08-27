#!/usr/bin/env ruby
require 'aws-sdk-core'
require 'pp'

support=Aws::Support::Client.new(region:'us-east-1')

["en","ja"].each do |lang|
  begin
    support.describe_cases(
      include_resolved_cases: true,
      language: lang,
      include_communications: false
    ).map{|page| page.cases}.flatten.each do |c|
#      pp c
      case_id=c.case_id
      display_id=c.display_id
      puts display_id
      begin
        support.describe_communications(
          case_id: case_id
        ).map{|page| page.communications}.flatten
        .select {|comm| comm.submitted_by != "Amazon Web Services <no-reply-aws@amazon.com>"}
        .each do |comm|
          puts comm.submitted_by+"\n"+comm.body
        end
      rescue Aws::Support::Errors::ServiceError => evar
        puts "INFO: communications were lost."
      end
    end
  rescue Aws::Support::Errors::ServiceError => evar
    pp evar
  end
end
