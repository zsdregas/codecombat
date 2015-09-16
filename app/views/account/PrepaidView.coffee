RootView = require 'views/core/RootView'
template = require 'templates/account/prepaid-view'
stripeHandler = require 'core/services/stripe'
{getPrepaidCodeAmount} = require '../../core/utils'
CocoCollection = require 'collections/CocoCollection'
Prepaid = require '../../models/Prepaid'
utils = require 'core/utils'

module.exports = class PrepaidView extends RootView
  id: 'prepaid-view'
  template: template
  className: 'container-fluid'

  events:
    'change #users': 'onUsersChanged'
    'change #months': 'onMonthsChanged'
    'click #purchase-button': 'onPurchaseClicked'
    'click #redeem-button': 'onRedeemClicked'

  subscriptions:
    'stripe:received-token': 'onStripeReceivedToken'

  baseAmount: 9.99

  constructor: (options) ->
    super(options)
    @purchase =
      total: @baseAmount
      users: 3
      months: 3
    @updateTotal()

    @codes = new CocoCollection([], { url: '/db/user/'+me.id+'/prepaid_codes', model: Prepaid })
    @codes.on 'add', (code) =>
      @render?()
    @codes.on 'sync', (code) =>
      @render?()

    @supermodel.loadCollection(@codes, 'prepaid', {cache: false})
    @ppc = utils.getQueryVariable('_ppc') ? ''

  getRenderData: ->
    c = super()
    c.purchase = @purchase
    c.codes = @codes
    c.ppc = @ppc
    c

  uiMessage: (message, type='alert') ->
    noty text: message, layout: 'topCenter', type: type, killer: false, timeout: 5000, dismissQueue: true, maxVisible: 3

  updateTotal: ->
    @purchase.total = getPrepaidCodeAmount(@baseAmount, @purchase.users, @purchase.months)
    @render()

  # Form Input Callbacks
  onUsersChanged: (e) ->
    newAmount = $(e.target).val()
    newAmount = 1 if newAmount < 1
    @purchase.users = newAmount
    @purchase.months = 3 if newAmount < 3 and @purchase.months < 3
    @updateTotal()

  onMonthsChanged: (e) ->
    newAmount = $(e.target).val()
    newAmount = 1 if newAmount < 1
    @purchase.months = newAmount
    @purchase.users = 3 if newAmount < 3 and @purchase.users < 3
    @updateTotal()

  onPurchaseClicked: (e) ->
    @purchaseTimestamp = new Date().getTime()
    @stripeAmount = @purchase.total * 100
    @description = "Prepaid Code for " + @purchase.users + " users / " + @purchase.months + " months"

    stripeHandler.open
      amount: @stripeAmount
      description: @description
      bitcoin: true
      alipay: if me.get('chinaVersion') or (me.get('preferredLanguage') or 'en-US')[...2] is 'zh' then true else 'auto'

  onRedeemClicked: (e) ->
    @ppc = $('#ppc').val()
    @uiMessage "You must enter a code.", "error"
    return unless @ppc
    button = e.target
    @redeemText = $(e.target).text()
    $(button).text('Redeeming...')
    button.disabled = true

    options =
      url: '/db/subscription/-/subscribe_prepaid'
      method: 'POST'
      data: { ppc: @ppc }

    options.error = (model, res, options) =>
      console.error 'FAILED redeeming prepaid code'
      button.disabled = false
      $(button).text(@redeemText)
      @uiMessage "Error: Could not redeem prepaid code", "error"

    options.success = (model, res, options) =>
      console.log 'SUCCESS redeeming prepaid code'
      @uiMessage "Prepaid Code Redeemed!", "success"
      button.disabled = false
      $(button).text(@redeemText)
      @supermodel.loadCollection(@codes, 'prepaid', {cache: false})
      @codes.fetch()
      @render?()

    @supermodel.addRequestResource('subscribe_prepaid', options, 0).load()

  onStripeReceivedToken: (e) ->
    # TODO: show that something is happening in the UI
    options =
      url: '/db/prepaid/-/purchase'
      method: 'POST'

    options.data =
      amount: @stripeAmount
      description: @description
      stripe:
        token: e.token.id
        timestamp: @purchaseTimestamp
      type: 'terminal_subscription'
      maxRedeemers: @purchase.users
      months: @purchase.months

    options.error = (model, response, options) =>
      console.error 'FAILED: Prepaid purchase', response
      console.error options
      @uiMessage "Error purchasing prepaid code", "error"
      # Not sure when this will happen. Stripe popup seems to give appropriate error messages.

    options.success = (model, response, options) =>
      console.log 'SUCCESS: Prepaid purchase', model.code
      @uiMessage "Successfully purchased Prepaid Code!", "success"
      @codes.add(model)

    @uiMessage "Finalizing purchase...", "information"
    @supermodel.addRequestResource('purchase_prepaid', options, 0).load()

