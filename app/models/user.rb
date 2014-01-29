class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable

  # :registerable removed because I don't want other people registering!
  # :recoverable removed because I don't want people spamming me with password reset requests
  devise :database_authenticatable, :rememberable, :trackable, :validatable
end
