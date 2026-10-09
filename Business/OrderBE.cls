/*------------------------------------------------------------------------------
 File        : Business.OrderBE
 Purpose     : 
 Syntax      : 
 Description :  
 Author(s)   : Code generator Pmfo.Tools.AppBuilder.CodeGenerator
 Created     : 07/14/2026 06:55:09.217-04:00
 Notes       :   
------------------------------------------------------------------------------*/

block-level on error undo, throw.

using Business.ItemBE from propath.
using Pmfo.Core.BusinessLogic.BusinessEntity from propath.
using Pmfo.Core.BusinessLogic.IUpdateDataRequest from propath.
using Pmfo.Core.Manager.ServiceManager from propath.
using Pmfo.Util.Array from propath.
using Pmfo.Util.DatasetUtil from propath.
using Progress.Lang.Object from propath.

class Business.OrderBE inherits BusinessEntity:

    {schema/order.i}
    {schema/orderline.i}
    
    define dataset dsOrder for ttOrder, ttOrderLine
       data-relation order-lines for ttOrder, ttOrderLine relation-fields(orderNum,orderNum) nested foreign-key-hidden
       .
    
    // use to update inventory from orderline changes - Submitdata will grab the data form there and submit with order/orderlines 
    define protected property ItemBe as ItemBE no-undo get. set.
    
    constructor OrderBE():
        super(dataset dsOrder:handle).
    end constructor.
    
    method protected override void ValidateData(pRequest as IUpdateDataRequest, input dataset-handle phDataset ): 
        ValidateStaticData(dataset-handle phDataset by-reference ). 
    end method.    
   
    method protected void ValidateStaticData(input dataset dsOrder ):
        define variable dExtendedPrice as decimal no-undo.
        
        for each ttOrder where row-state(ttOrder) > 0:
            if ttOrder.shipDate = ? then 
            do:
                AddWarning("Shipdate was not submitted on Order. Set to today + 7").
                ttOrder.shipDate = today +  7.
            end.     
            for each ttOrderline where ttOrderLine.Ordernum = ttOrder.OrderNum and row-state(ttOrderLine) > 0:
                dExtendedPrice = ttOrderline.Price * ttOrderLine.Qty * (1 - (ttOrderLine.Discount / 100)).
                if ttOrderline.ExtendedPrice > 0 and ttOrderline.ExtendedPrice <> dExtendedPrice then 
                    ThrowBufferError(buffer ttOrderLine:handle,
                                     substitute("Order &1 Line &2 Extended Price &3 is not valid. The Extended Price will be calculated if submitted as 0 or empty",
                                                 ttOrderLine.OrderNum,
                                                 ttOrderLine.LineNum,
                                                 ttOrderline.ExtendedPrice
                                     ),
                                    "extendedPrice").
                assign ttOrderline.ExtendedPrice = dExtendedPrice.          
            end.
        end.    
        
        if not valid-object(ItemBe) then 
            ItemBE = cast(ServiceManager:CreateBusinessEntity('items'),ItemBE).
        
        /* Call Item Be to validate and update item allocated - will be added to the submiot dataset in SubmitData
           TODO: This is an anti-pattern. Fix this to not expect this-object */   
        ItemBe:ValidateAndUpdateInventory(this-object, table ttOrderLine by-reference).
            
    end method.    
    
    // override to submit the server dataset with xrefs to dataacces 
    method protected override Object SubmitData(input poUpdateDataRequest as IUpdateDataRequest, input-output dataset-handle phDataset):
        define variable hDataset as handle no-undo.
        // use itembe to submit items with onorder updated  
        if valid-object(ItemBE)  then    
            hDataset = DatasetUtil:CreateDatasetFromMultipleDatasets(Array:ToArray(ItemBE:GetItemInventoryDataForSubmit(),phDataset)).
        else 
            hDataset = phDataset.
       
        super:SubmitData(poUpdateDataRequest, input-output dataset-handle hDataset by-reference). 
        finally:
            // do not delete phdataset - it may be dynamic, but needs to returned to client  
            if valid-object(hDataset) and hDataset <> phDataset and hDataset:dynamic  then
                delete object hDataset.
          
            /* delete ItemBe since it may have a cross reference since we passed this-object to it
               (destructor will not be called in that case) 
               This must be done after submit since the ttItem data is passed to data access 
               The phdataset does not have ttItem so deleting does not dause problems for client */    
            if valid-object(ItemBe) then 
                delete object ItemBE.     
        end.
    end method.    
end class.
