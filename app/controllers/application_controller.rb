class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  check_authorization :unless => :devise_controller?

  helper_method :current_or_guest_user

  before_filter :logging_in

  def current_user_role_key
    return 'anonymous' unless current_user
    [
      current_user.role.to_s,
      current_user.local_administration_unit_admins.map do |laur|
        "#{laur.local_administration_unit_id}:#{laur.role}"
      end
    ].join('::')
  end

  # Folowing code is for Guest User
  # it is done by https://github.com/plataformatec/devise/wiki/How-To:-Create-a-guest-user

  # if user is logged in, return current_user, else return guest_user
  def current_or_guest_user
    if current_user
      if session[:guest_user_id] && session[:guest_user_id] != current_user.id
        logging_in
        # reload guest_user to prevent caching problems before destruction
        guest_user(with_retry = false).reload.try(:destroy)
        session[:guest_user_id] = nil
      end
      current_user
    else
      guest_user
    end
  end

  # find guest_user object associated with the current session,
  # creating one as needed
  def guest_user(with_retry = true)
    # Cache the value the first time it's gotten.
    @cached_guest_user ||= User.find(session[:guest_user_id] ||= create_guest_user.id)

  rescue ActiveRecord::RecordNotFound # if session[:guest_user_id] invalid
     session[:guest_user_id] = nil
     guest_user if with_retry
  end

  private

  # called (once) when the user logs in, insert any code your application needs
  # to hand off from guest_user to current_user.
  def logging_in
    return unless session[:guest_user_id] and user_signed_in?

    Rails.logger.info "Copying #{guest_user.notifications.count} " \
                      "notifications from guest_user:#{guest_user.id} to " \
                      "current_user:#{current_user.id}"
    guest_notifications = guest_user.notifications.all
    guest_notifications.each do |notification|
      notification.user_id = current_user.id
      notification.save!
    end

    if session[:guest_user_id]
      Rails.logger.info "Removing guest_user #{session[:guest_user_id]}"
      begin
        User.find(:guest_user_id).destroy
      rescue ActiveRecord::RecordNotFound
      end
      session[:guest_user_id] = nil
    end
  end

  def create_guest_user
    u = User.create(:email => "guest_#{Time.now.to_i}#{rand(100)}@example.com")
    u.save!(:validate => false)
    session[:guest_user_id] = u.id
    Rails.logger.debug "Created guest user:#{u.id} email:#{u.email}"
    u
  end

end
