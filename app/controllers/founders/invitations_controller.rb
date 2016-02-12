module Founders
  class InvitationsController < Devise::InvitationsController
    def edit
      # don't repeat registration if already completed
      if resource.already_registered?
        sign_in resource
        session[:registration_ongoing] = true
        redirect_to phone_verification_founder_path, alert: 'You have already completed your user registration!'
      else
        @skip_container = true
        super
      end
    end

    def after_accept_path_for(_resource)
      session[:registration_ongoing] = true
      phone_verification_founder_path
    end

    private

    # this is called when creating invitation
    # should return an instance of resource class
    def invite_resource
      ## skip sending emails on invite
      resource_class.invite!(invite_params, current_inviter) do |u|
        u.skip_invitation = true
      end
    end

    # this is called when accepting invitation
    # should return an instance of resource class
    def accept_resource
      resource = resource_class.accept_invitation!(update_resource_params)
      resource.update_attributes(startup: nil) if update_resource_params[:accept_startup] == '0' && resource.valid?
      resource
    end
  end
end
