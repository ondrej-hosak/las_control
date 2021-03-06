class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new

    if user.admin?
      can :manage, :all
    else
      can [:read], Document, Document.lau_permitted(user) do |document|
        by_time = Time.now
        (
          document.published &&
          (document.pii_public_until.nil? || by_time < document.pii_public_until)
        ) || (
          user.lau_permitted?(document.local_administration_unit)
        )
      end

      can :create, Document, local_administration_unit_id: user.local_administration_unit_admins.first&.local_administration_unit&.id
      can [:edit, :update], Document do |document|
        document.created_by &&
        user.local_administration_unit_admins.pluck(
          :local_administration_unit_id
        ).include?(document.local_administration_unit_id)
      end

      can [:update], User, id: user.id
      can [:read, :options], LocalAdministrationUnit


      # LAU operator and admin can see LocalAdministrationUnitAdmin for its LAU
      can [:read],
        LocalAdministrationUnitAdmin,
        LocalAdministrationUnitAdmin do |las_admin|
          las_admin.user == user
        end
      # LAU admin can change LAU admis for its LAU
      can [:create, :update, :destroy],
        LocalAdministrationUnitAdmin,
        LocalAdministrationUnitAdmin do |las_admin|
          lau = las_admin.local_administration_unit
          lau && lau.local_administration_unit_admins.where(
            user: user,
            role: 'admin'
          ).present?
        end

      # LAU Admin and Operator can change emails for LAU
      can :manage, IncomeEmailAddress do |income_email|
        lau = income_email.local_administration_unit
        lau && lau.local_administration_unit_admins.where(
          user: user
        ).present?
      end

      can [:read], Event, Event.lau_permitted(user) do |event|
        by_time = Time.now
        event.source && (
          (
            event.source.published &&
            (
              event.source.pii_public_until.nil? ||
              by_time < event.source.pii_public_until
            ) &&
            event.removed_by_id.nil?
          ) || (
            user.lau_permitted?(event.source.local_administration_unit)
          )
        )
      end

      can [:read], AddressBlock do |address_block|
        can? :read, address_block.source
      end

      can [:read], Shape #TODO, really? or allow only the ones with readable events?
      can :manage, Notification, { user_id: user.id }
    end
  end
end
