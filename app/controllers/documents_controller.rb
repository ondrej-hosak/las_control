class DocumentsController < ApplicationController
  skip_authorization_check only: [:index, :show]
  load_and_authorize_resource :document

  def new
    @document = Document.new(
      from_date: Date.today,
      local_administration_unit: current_user&.local_administration_unit_admins&.first&.local_administration_unit,
      tags: 'upload'
    )
    @document.assign_attributes(current_ability.attributes_for(action_name.to_sym, Document))
  end

  def create
    @document = Document.new(
      current_ability.attributes_for(action_name.to_sym, Document).merge(document_create_params)
    )

    if @document.url.present? and @document.document_storage
      flash.alert = "Přiložený dokument byl ignorován a bude stažen ze zadané URL"
      @document.document_storage = nil
    end

    @document.created_by = current_user

    respond_to do |format|
      if (@document.document_storage || @document.valid_url?) && @document.save
        format.html { redirect_to @document, notice: 'Dokument byl vytvořen a zařazen do fronty na zpracování.' }
        format.json { render :show, status: :created, location: @document }
      else
        puts @document.errors.full_messages
        format.html { render :new }
        format.json { render json: @document.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      if @document.update(document_params)
        format.html { redirect_to @document, notice: 'Změny v dokumentu uloženy.' }
        format.json { render :show, status: :ok, location: @document }
      else
        format.html { render :edit }
        format.json { render json: @document.errors, status: :unprocessable_entity }
      end
    end
  end

  def index
    @q = Document.ransack(params[:q])
    @q.sorts = 'from_date desc' if @q.sorts.empty? && !params[:query]

    @collection = @q
      .result
      .accessible_by(current_ability)
      .includes(local_administration_unit: :ruian_locable)
      .page params[:page]

    lau_filter = params[:q] ? params[:q][:local_administration_unit_id_eq] : nil
    @local_administration_unit =
      LocalAdministrationUnit.find_by(id: lau_filter) ||
      LocalAdministrationUnit.new
    @query = params[:query]

    # Use Elasticserch if query param is used
    if params[:query].present?
      @elasticsearch = true
      @collection = Document.elasticsearch_search(
        params[:query],
        sort: params[:q].try(:[], :s),
        local_administration_unit_id: lau_filter
      ).page(params[:page]) #.results
      @records = @collection.records
    else
      @elasticsearch = false
    end
  end

  def show
    @document = Document.includes(
      address_blocks: { events: :shape_with_definition_point }
    ).accessible_by(current_ability).find(params[:id])
    authorize! :show, @document
  end

  private


  def document_params
    params.require(:document).permit(
      :title,
      :local_administration_unit_id,
      :official_notice_board_category_id,
      :url,

      :from_date,
      :file_number
    )
  end

  def document_create_params
    params.require(:document).permit(
      :title,
      :local_administration_unit_id,
      :official_notice_board_category_id,
      :url,

      :from_date,
      :file_number,

      :document_storage,
      :retained_document_storage,
      :remove_document_storage,
    )
  end
end
