require 'mechanize'
require 'active_model'
require 'json'
require 'zip'
require 'tempfile'
require 'cgi'

class XQueueSubmission
  class InvalidSubmissionError < StandardError ;  end

  # The +XQueue+ from which this assignment was retrieved (and to which the grade should be posted back)
  attr_reader :queue
  # XQueue-server-supplied nonce that will be needed to post back a grade for this submission
  attr_reader :secret
  # XML data encoded from edX sent as a string with the submission. XQueueSubmission stores this internally as a hash if it is a JSON.
  # Otherwise, will be stored as a string if cannot be parsed as JSON. http://edx-partner-course-staff.readthedocs.org/en/latest/exercises_tools/external_graders.html
  attr_reader :grader_payload
  # When student submitted assignment via edX (a Time object)
  attr_reader :submission_time
  # one-way hash of edX student ID
  attr_reader :student_id
  # Numeric: score reported by autograder
  attr_accessor :score
  # String: textual feedback from autograder
  attr_accessor :message
  # Boolean: if +true+ when posted back, shows green checkmark, otherwise red X
  attr_accessor :correct
  # Hash: files submitted by student. If #fetch_files! flag not set, then values will be URI strings to remote locations
  # if flag is set, then will contain string of fetched files.
  # if #write_to_location! is called, then values will be URI strings pointing to local files.
  attr_reader :files
  #used by RAG https://github.com/saasbook/rag to store grader_payload information.
  attr_accessor :assignment

  # A Hash of default values used for initializing a XQueueSubmission
  DEFAULTS = {correct: false, score: 0, message: '', errors: ''}
  def initialize(hash)
    begin
      fields_hash = DEFAULTS.merge(hash)
      fields_hash.each {|key, value| instance_variable_set("@#{key}", value)}
    rescue NoMethodError => e
      if e.message == "undefined method `[]' for nil:NilClass"
        raise InvalidSubmissionError, "Missing element(s) in JSON: #{hash}"
      end
      raise e
    end
  end


  # Puts a properly formatted response containing fields @secret, @score, @correct, html formatted @message back into
  # the XQueue this submission was created from.
  def post_back
    @queue.put_result(@secret, @score, @correct, @message.prepend('<pre>').concat('</pre>'))
  end



  # A convenience method for external autograders to submit a normalized score and comments to edX.
  #--
  def grade!(comments, score, total_score=100.0)
    @message = "Score: #{score}/#{total_score}\n" + @message << comments
    @score = score.to_f / total_score * 100  # make this out of 100 since that seems to be default
    @correct = total_score == score
  end
  # call on XQueueSubmission to fetch the files if remote format and return XQueueSubmission
  def fetch_files!
    if files
      file_agent = Mechanize.new
      @files = @files.inject({}) {|new_hash, (k,v)| new_hash[k] = file_agent.get_file(v); new_hash}
    end
    self
  end

  # call on XQueueSubmission to write files that have already been fetched and writes them to a specified location.
  def write_to_location!(root_file_path)

    FileUtils.mkdir_p root_file_path
    @files.each do |file_name, contents|
      if file_name.include? '.zip'
        unzip root_file_path, contents
      else
        File.open(File.join(root_file_path, file_name), 'w') { |file| file.write(contents); file }
      end
      @files[file_name] = root_file_path  # after we write to location, change the values so that it points to the places on disk where the files can be found
    end
  end 


  # Given an XQueue and a JSON string, returns the appropriate XQueueSubmission object
  def self.create_from_JSON(xqueue, json_response)

    # json_response = recursive_JSON_parse(json_response)
   puts json_response['xqueue_files']
  header, files, body = json_response['xqueue_header'], json_response['xqueue_files'], json_response['xqueue_body']
  puts body

    grader_payload = body['grader_payload']
    anonymous_student_id, submission_time = body['student_info']['anonymous_student_id'], Time.parse(body['student_info']['submission_time'])
    XQueueSubmission.new({queue: xqueue, secret: header, files: files, student_id: anonymous_student_id, submission_time: submission_time, grader_payload: grader_payload})
  end

  # The JSON we receive from the server is nested JSON hashes. Rather than calling JSON.parse at each level to get the JSON we choose to expand it into a multi-level hash immediately for easy
  # access
  def self.recursive_JSON_parse(obj, i=0)
    valid_json_hash = try_parse_JSON(obj)
    if i > 100
      raise "Depth level exceeded in recursive_JSON_parse, depth level : #{i}"
    end
    if valid_json_hash
      valid_json_hash.update(valid_json_hash) do |_key, value|
        value = recursive_JSON_parse(value, i + 1)
      end
      return valid_json_hash
    else
      return obj
    end
  end

  #returns nil if the object is not JSON
  def self.try_parse_JSON(obj)
    begin
      JSON.parse(obj)
    rescue Exception
       nil
    end
  end

  protected
  # +contents+ is a string representing a zip file. Unzips to +root_location+
  #--
  # Source for zipping code:
  # http://stackoverflow.com/questions/19754883/how-to-unzip-a-zip-file-containing-folders-and-files-in-rails-while-keeping-the
  def unzip(root_location, contents)
    tmp_zip = Tempfile.open('zip_file') {|tmp| tmp.write(contents); tmp}  # block should yield tmp at end
    Zip::File.open(tmp_zip.path) do |zip_file|
      zip_file.each do |f|
        f_path = File.join(root_location, f.name)
        FileUtils.mkdir_p(File.dirname(f_path))
        zip_file.extract(f, f_path) unless File.exist?(f_path)
      end
    end
  end
end
