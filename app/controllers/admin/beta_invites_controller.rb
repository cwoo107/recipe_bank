# Sign-up links for beta testers while public sign-up is closed (Launch).
# Each link is for one person and works once; copy it and send it however
# suits — nothing is emailed from here.
class Admin::BetaInvitesController < Admin::BaseController
  def index
    @invites = BetaInvite.includes(:created_by, :redeemed_by).newest_first
  end

  def create
    invite = BetaInvite.create!(name: params[:name].to_s.strip.presence, created_by: current_user)
    redirect_to admin_beta_invites_path(highlight: invite.id),
                notice: "Invite link created — copy it below and send it on.", status: :see_other
  end

  # Only an unused link can be withdrawn; a used one stays as the record of
  # who joined with it.
  def destroy
    invite = BetaInvite.unredeemed.find(params[:id])
    invite.destroy!
    redirect_to admin_beta_invites_path, notice: "Invite link revoked.", status: :see_other
  end
end
