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
    # TODO: error message if there's no code entered?
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
      # TODO: display UI error message

    options.success = (model, res, options) =>
      console.log 'SUCCESS redeeming prepaid code'
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
      # TODO: display a UI error message

    options.success = (model, response, options) =>
      console.log 'SUCCESS: Prepaid purchase', model.code
      @codes.add(model)

    @supermodel.addRequestResource('purchase_prepaid', options, 0).load()

