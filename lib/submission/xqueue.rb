require_relative '../xqueue_ruby'
require_relative '../assignment/xqueue'
require_relative 'polling'

module Submission
  ENV['BASE_FOLDER'] ||= 'submissions/'
  FileUtils.mkdir ENV['BASE_FOLDER'] unless File.exist? ENV['BASE_FOLDER']
  class Xqueue < Polling
    attr_reader :x_queue

    STRFMT = "%Y-%m-%d-%H-%M-%S"
    def initialize(config_hash)
      super(config_hash)
      @x_queue = ::XQueue.new(*create_xqueue_hash(config_hash))
      @@logger.debug('Successfully started an XQueue submission adapter.')
    end

    def next_submission_with_assignment
      # submission = @x_queue.get_submission
      submission=XQueueSubmission.new({
        queue: @x_queue, 
        secret: {"submission_id"=> "729546",  "submission_key"=>  "c682677d07bdea26755a5e966edd2982"}, 
        files:{'hw5.rb'=>'http://localhost:8080/examples/hw5.txt'}, 
        student_id: "12334", 
        submission_time: Time.gm(2015,12,23,23,59,59),
        grader_payload: { "assignment_name"=>  "assignment5",
                   "assignment_spec_uri"=>  "http://localhost:8080/examples/hw5spec.txt",
                "autograder_type"=>  "HW5Grader",
                "due_dates"=>{
                   "2100-01-02"=> 1.0,  "2100-01-03"=> 0.75,  "2100-01-04"=> 0.50,
             "2100-01-05"=> 0.25
            } , 
             "student_response"=> " " 
             } 
        })
      return if submission.nil?
      
      submission.assignment = Assignment::Xqueue.new(submission)

      logger.info("XQueue adapter received submission. Student #{submission.student_id} assignment #{submission.assignment.assignment_name}")
      submission.write_to_location! File.join( [ENV['BASE_FOLDER'], submission.student_id].join(''),
                        submission.assignment.assignment_name, Time.new.strftime(STRFMT))
      submission
    end

    def submit_response(graded_submission)
      graded_submission.post_back
    end

    def create_xqueue_hash(config_hash)
      [
        config_hash['django_auth']['username'],  # django_name
        config_hash['django_auth']['password'],  # django_pass
        config_hash['user_auth']['user_name'],   # user_name
        config_hash['user_auth']['user_pass'],   # user_pass
        config_hash['queue_name']                # queue_name
      ]
    end
  end
end
