class XQueue
  require 'mechanize'
  require 'json'
  
  # Ruby interface to the Open edX XQueue class for external checkers
  # (autograders).  Lets you pull student-submitted work products from a
  # named queue and post back the results of grading them.
  #
  # All responses from the XQueue server have a JSON object with
  # +return_code+ and +content+ slots.  A +return_code+ of 0 normally
  # means success.  
  #
  # == Example
  #
  # You need two sets of credentials to authenticate yourself to the
  # xqueue server.  For historical reasons, they are called
  # (+django_name+, +django_pass+) and (+user_name+, +user_pass+).
  # You also need to name the queue you want to use; edX creates queues
  # for you.  Each +XQueue+ instance is tied to a single queue name.
  #
  # === Retrieving an assignment:
  #
  #     queue = XQueue.new('dj_name', 'dj_pass', 'u_name', 'u_pass', 'my_q')
  #     queue.length  # => an integer showing queue length
  #     assignment = queue.get_submission  # => returns new +XQueueSubmission+ object
  #
  # === Posting results back
  #
  # The submission includes a secret key that is used in postback,
  # so you should use the +#postback+ method defined on the submission.
  #

  # The base URI of the production Xqueue server.
  XQUEUE_DEFAULT_BASE_URI = 'https://xqueue.edx.org'

  # Error message, if any, associated with last unsuccessful operation
  attr_reader :error
  
  # Queue from which to pull, established in constructor.  You need a
  # new +XQueue+ object if you want to use a different queue.
  attr_reader :queue_name

  # The base URI used for this queue; won't change for this queue even
  # if you later change the value of +XQueue.base_uri+
  attr_reader :base_uri

  # The base URI used when new queue instances are created
  def self.base_uri
    @@base_uri ||= URI(XQUEUE_DEFAULT_BASE_URI)
  end
  def self.base_uri=(uri)
    @@base_uri = URI(uri)
  end

  class XQueueError < StandardError ; end
  # Ancestor class for all XQueue-related exceptions
  class AuthenticationError < XQueueError ;  end
  # Raised if XQueue authentication fails
  class IOError < XQueueError ; end
  # Raised if there are network or I/O errors connecting to queue server
  class NoSuchQueueError < XQueueError ; end
  # Raised if queue name doesn't exist
  class UpdateFailedError < XQueueError ; end
  # Raised if a postback to the queue (to post grade) fails at
  # application level

  # Creates a new instance and attempts to authenticate to the
  # queue server.  
  # * +django_name+, +django_pass+: first set of auth credentials (see
  # above)
  # * +user_name+, +user_pass+: second set of auth credentials (see
  # above)
  # * +queue_name+: logical name of the queue
  # * +retrieve_files+: boolean option to retrieve file named in xqueue_files in XQueueSubmission
  def initialize(django_name, django_pass, user_name, user_pass, queue_name, retrieve_files=true)
    @queue_name = queue_name
    @base_uri = XQueue.base_uri
    @django_auth = {'username' => django_name, 'password' => django_pass}
    @session = Mechanize.new
    @session.add_auth(@base_uri, user_name, user_pass)
    @valid_queues = nil
    @error = nil
    @authenticated = nil
    @retrieve_files = retrieve_files
  end

  # Authenticates to the server.  You can call this explicitly, but it
  # is called automatically if necessary on the first request in a new
  # session.  
  def authenticate
    response = request :post, '/xqueue/login/', @django_auth
    @authenticated = true

    if response['return_code'] == 0
      @authenticated = true
    else
      # raise(AuthenticationError, "Authentication failure: #{response['content']}")
    end
  end

  # Returns +true+ if the session has been properly authenticated to
  # server, that is, after a successful call to +authenticate+ or to any
  # of the request methods that may have called +authenticate+ automatically.
  def authenticated? ; @authenticated ; end

  # Returns length of the queue as an integer >= 0.
  def queue_length
    #authenticate unless authenticated?
    return 1
    response = request(:get, '/xqueue/get_queuelen/', {:queue_name => @queue_name})
    if response['return_code'] == 0 # success
      response['content'].to_i
    elsif response['return_code'] == 1 && response['content'] =~ /^Valid queue names are: (.*)/i
      @valid_queues = $1.split(/,\s+/)
      raise NoSuchQueueError, "No such queue: valid queues are #{$1}"
    else
      raise IOError, response['content']
    end
  end
  # Displays the list of queues.
  def list_queues
    #authenticate unless authenticated?
    if @valid_queues.nil?
      old, @queue_name = @queue_name, 'I_AM_NOT_A_QUEUE'
      begin queue_length rescue nil end
    end
    @valid_queues
  end
  # Retrieve a submission from this queue. If retrieve files set to true, also gets files from URI if necessary.
  # Returns nil if queue is empty,
  # otherwise a new +XQueue::Submission+ instance.
  def get_submission
    #authenticate unless authenticated?
    puts "so"
    if queue_length > 0
      begin
       # json_response = request(:get, '/xqueue/get_submission/',  {:queue_name => @queue_name})
        json_response={
          "content"=>{
            "xqueue_files"=> {
              "hw5.rb"=>"http://localhost:8080/examples/hw5.txt"},
              "xqueue_header"=>{
                "submission_id"=>729546,
                "submission_key"=>"c682677d07bdea26755a5e966edd2982"
                },
              "xqueue_body"=>{
                  "student_info"=>{
                    "anonymous_student_id"=>"506af89a6181960fc69f47f1fbc8d708",
                    "submission_time"=>"50000619185228"
                    },
              "grader_payload"=>{
                      "assignment_name"=>"assignment5",
                      "assignment_spec_uri"=>"http://localhost:8080/examples/hw5spec.txt",
                      "autograder_type"=>"HW5Grader",
                      "due_dates"=>{
                        "2100-01-02"=>1.0,
                        "2100-01-03"=>0.75,
                        "2100-01-04"=>0.50,
                        "2100-01-05"=>0.25
                        }
                },
              "student_response"=>""
                    }
          },
          "return_code"=>0
      }
       # if json_response['return_code'] == 1
        #   @retrieve_files ? XQueueSubmission.create_from_JSON(self, json_response['content']).fetch_files! :
        tt={'con'=> '123'}
    
        XQueueSubmission.create_from_JSON(self,json_response['content'])
        # else
        #   raise "Non-standard response received, JSON dump: #{json_response.pretty_generate}"
        # end
      # rescue StandardError => e  # TODO: do something more interesting with the error.
        # raise e
      end
    else
      nil
    end
  end
  # Record a result of grading something.  It may be easier to use
  # XQueueSubmission#post_back, which marshals the information
  # needed here automatically.
  #
  # * +header+: secret header key (from 'xqueue_header' slot in the
  # 'content' object of the original retrieved submission)
  # * +score+: integer number of points (not scaled)
  # * +correct+: true (default) means show green checkmark, else red 'x'
  # * +message+: (optional) plain text feedback; will be coerced to UTF-8

  def put_result(header, score, correct=true, message='')
    xqueue_body =   JSON.generate({
                  :correct   => (!!correct).to_s.capitalize,  # valid is True or False
                  :score     => score,
                  :msg   => message.encode('UTF-8',
                    :invalid => :replace, :undef => :replace, :replace => '?'),
                                  })
    payload = {xqueue_header: JSON.generate(header), xqueue_body: xqueue_body}
    response = request :post, '/xqueue/put_result/', payload
    if response['return_code'] != 0
      raise UpdateFailedError, response['content']
    end
  end

  private

  # :nodoc:
  def request(method, path, args={})
    begin
      response = @session.send(method, @base_uri + path, args)
      response_json = JSON.parse(response.body)
    rescue Mechanize::ResponseCodeError => e
      raise IOError, "Error communicating with server: #{e.message}"
    rescue JSON::ParserError => e
      raise IOError, "Non-JSON response from server: #{response.body.force_encoding('UTF-8')}"
    rescue Exception => e
      raise IOError, e.message
    end
  end
end
