require 'rspec'
require 'json'
require_relative 'json_points_formatter'
module Graders
  class FileIO < StringIO
    def initialize(filename, mode = 'w')
      super('',mode)
      @mode = mode
      @file = File.open(filename, mode)
    end
    def << obj
      if @mode == 'w'
        @file.write(obj)
      end
    end
    def close
      @file.close
      super.close
    end
  end
  class RspecGrader < AutoGrader
    class RspecGrader::NoSuchSpecError < StandardError ; end
    class RspecGrader::NoSpecsGivenError < StandardError ; end

    # The constructor is called from +AutoGrader.create+ so you shouldn't call
    # it directly.  The required and optional grading rules for
    # +RspecGrader+ are:
    # * +:spec+ - the full pathname to a specfile that will be run
    #   against the student's code.  The spec should <b>not</b> try to
    #   +require+ or +include+ the subject code file, but it can +require+
    #   or +include+ any other Ruby libraries needed for the specs to run.

    ERROR_HASH = {raw_score: 0, raw_max: 100, comments: 'There was a fatal error with your submission. It either timed out or caused an exception.'}
    def initialize(submission_path, assignment)
      super(submission_path, assignment)
      @timeout = 50
      @spec_file_path = assignment.assignment_spec_file
      raise NoSuchSpecError, 'Specs could not be found' unless File.readable? @spec_file_path
      @load_student_files = true  # True if you need to load student files into testing subprocess namespace. HerokuGrader and subclasses do not load student code.
    end

    def grade
      response = run_in_subprocess(method(:runner_block))
      if response
        response
      else
        ERROR_HASH
      end
    end
    
    # call by runner_block which will be called in run_in_subprocess of submission_ruby
    def compute_points (file_path)
      errs = StringIO.new('', 'w')
      output = StringIO.new('', 'w')
      
      points_max = 0
      points = 0
      RSpec.reset
      RSpec.configure do |config|
        config.formatter = 'documentation'
        config.formatter = 'RSpec::Core::Formatters::JsonPointsFormatter'
        config.formatter = 'RSpec::Core::Formatters::BaseFormatter'
      end
      begin
        # TODO: to learning the RSpec::Core::Runner how to work
        #       and how to get the detail of rspec report
        RSpec::Core::Runner.run([file_path], errs, output)
        # Note: formatter select point message from Rspec running message
        formatter = RSpec.configuration.formatters.select {|formatter| formatter.is_a? RSpec::Core::Formatters::JsonPointsFormatter}.first
        output_hash = formatter.output_hash
        output_hash[:examples].each do |example|
          points_max += example[:points]
          points += example[:points] if example[:status] == 'passed'
        end
        # formatter select resport
        formatter = RSpec.configuration.formatters.select {|formatter| formatter.is_a? RSpec::Core::Formatters::BaseFormatter}.first
        output_hash = formatter.output_hash
        puts output_hash
      rescue Exception => e
        logger.warn("RSpec::Core::Runner encountered #{e.to_s}")
        logger.warn("Errors is:\n#{output.string}")
      end

      cleaned_output = output.string.split(/\n/).select{|b| !b.match(/^    *# .*/) }.join("\n").gsub(file_path, 'your_code.rb')  # Removes large stacktraces and tmpfile from error messages.
      if e.nil?
        {raw_score: points, raw_max: points_max, comments: [cleaned_output, errs.string].join("\n")}
      else
        {raw_score: points, raw_max: 100, comments: e.to_s}
      end
    end

    def runner_block
      if File.directory? @spec_file_path
        combined_grade_hash = {}
        Dir[File.join(@spec_file_path, '*.rb')].each do  |spec_file|
          rspec_combined = Graders.join_student_and_spec_files(@submission_path, spec_file) if @load_student_files
          combined_grade_hash = combined_grade_hash.merge(compute_points(rspec_combined || spec_file)) {|key, accumulated_val, val| accumulated_val + val}
        end
        combined_grade_hash
      else
        rspec_combined = Graders.join_student_and_spec_files(@submission_path, @spec_file_path) if @load_student_files
        compute_points(rspec_combined || @spec_file_path)
      end
    end
  end
end