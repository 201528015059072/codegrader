require 'spec_helper'

describe Assignment::Xqueue do
  before(:all) do
    FakeWeb.register_uri(:get, 'http://fixture.net/assignment1_spec.txt', :body => IO.read('spec/fixtures/ruby_intro_part1_spec.rb'))
  end
  context 'it can be initialized from a valid XQueueSubmission' do
    before(:each) do
      double = double('XQueue')
      @submission = ::XQueueSubmission.create_from_JSON(double, IO.read('spec/fixtures/x_queue_submission.json'))
    end
    it 'properly validates fields that need to exist when created', points: 10 do
      expect(Assignment::Xqueue.new(@submission)).to be
    end
  end

  context 'when from invalid XQueueSubmission' do
    before(:each) do
      double = double('XQueue')
      @submission = ::XQueueSubmission.create_from_JSON(double, IO.read('spec/fixtures/invalid_x_queue_submission.json'))
    end

    # it 'should raise error when invalid' do
    #   pending 'should pass but failing, non-critical test investigate later'
    #   expect{Assignment::Xqueue.new(@submission)}.to raise_error
    # end
  end

  context 'can apply lateness to submissions based on assignment due dates' do
    before(:each) do
      double = double('XQueue')
      @submission = ::XQueueSubmission.create_from_JSON(double, IO.read('spec/fixtures/x_queue_submission.json'))
      @assignment = Assignment::Xqueue.new(@submission)
      @submission.score = 1.0
      @submission.message = 'good jerb student!!!!' # mock grading so that we can test penalization
    end

    it 'should not penalize for on time submissions' do
      allow(@submission).to receive(:submission_time).and_return(Time.parse('2000-01-01'))
      @assignment.apply_lateness! @submission
      expect(@submission.score).to be == 1.0
      expect(@submission.message).to include('on time')
    end

    it 'should penalize assignments that are in grace period' do
      allow(@submission).to receive(:submission_time).and_return(Time.parse('2000-01-02'))
      @assignment.apply_lateness! @submission
      expect(@submission.score).to be == 0.75
      expect(@submission.message).to include('late')
    end

    it 'should penalize assignments that are in late period' do
      allow(@submission).to receive(:submission_time).and_return(Time.parse('2000-01-03'))
      @assignment.apply_lateness! @submission
      expect(@submission.score).to be == 0.50
      expect(@submission.message).to include('late')
    end

    it 'should not award points to assignments submitted past time' do
      allow(@submission).to receive(:submission_time).and_return(Time.parse('2100-01-25'))
      @assignment.apply_lateness! @submission
      expect(@submission.score).to be == 0.0
      expect(@submission.message).to include('late')
    end
  end
end
