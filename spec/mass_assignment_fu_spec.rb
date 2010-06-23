require File.dirname(__FILE__) + '/spec_helper'

describe MockModel do
  it "should initialize attributes" do
    Student.new.attributes.should == Student.new.initial_attributes
    Grade.new.attributes.should == Grade.new.initial_attributes
    Profile.new.attributes.should == Profile.new.initial_attributes
  end
end

describe "MassAssignmentFu" do
  before :each do
    @student = Student.new
  end

  it "should protect immediate attributes" do
    @student.update_attributes_for :teacher, { :full_name => 'Jeff Joxworthy', :preferred_name => 'foxxy' }
    @student.attributes.should == @student.initial_attributes
  end

  it "should allow changes to immediate attributes" do
    @student.update_attributes_for(:student, { :preferred_name => 'Jeff' })
    @student.attributes.should == @student.initial_attributes.merge({'preferred_name' => 'Jeff'})
  end

  it "should allow updating and protect nested models" do
    @student.update_attributes_for(:administrator, { :preferred_name => 'Jeffery Fensworth', :grades_attributes => { '1' => Grade.new.initial_attributes.merge('letter_grade' => 'A', 'override_letter_grade' => 'A') } })
    @student.attributes.should == @student.initial_attributes.merge({'grades_attributes' => { '1' => Grade.new.initial_attributes.merge('override_letter_grade' => 'A') } })
  end

  it "should give access to all attributes when :all is specified" do
    @student.update_attributes_for(:student, { :profile_attributes => Profile.new.initial_attributes.merge('favorite_sport' => 'world cup') })
    @student.attributes.should == @student.initial_attributes.merge({'profile_attributes' => Profile.new.initial_attributes.merge('favorite_sport' => 'world cup') })
  end

  it "should fall back to using attr_accessible for nested models where attr_accessible_for is not specified" do
    @student.update_attributes_for(:teacher, { :grades_attributes => { '1' => Grade.new.initial_attributes.merge('class_id' => '15', 'letter_grade' => 'F', 'override_letter_grade' => 'F') } })
    @student.attributes.should == @student.initial_attributes.merge({'grades_attributes' => { '1' => Grade.new.initial_attributes.merge('class_id' => '15') } })
  end

  it "should handle arrays for nested associations" do
    array_attrs = @student.initial_attributes.merge('grades_attributes' => [Grade.new.initial_attributes])
    @student.attributes = array_attrs

    @student.update_attributes_for(:administrator, {'grades_attributes' => [Grade.new.initial_attributes.merge('override_letter_grade' => 'F', 'letter_grade' => 'F')] })
    @student.attributes.should == array_attrs.merge({'grades_attributes' => [Grade.new.initial_attributes.merge('override_letter_grade' => 'F')] })
  end

end
